defmodule Kalcifer.Integration.LiveMigrationTest do
  @moduledoc """
  End-to-end integration tests for live version migration.
  """
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Tenants

  @raw_api_key "live_migration_test_api_key"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  defp wait_graph(event_type, timeout \\ "3d") do
    %{
      "nodes" => [
        %{
          "id" => "entry_1",
          "type" => "event_entry",
          "position" => %{"x" => 0, "y" => 0},
          "config" => %{"event_type" => "signed_up"}
        },
        %{
          "id" => "wait_1",
          "type" => "wait_for_event",
          "position" => %{"x" => 100, "y" => 0},
          "config" => %{"event_type" => event_type, "timeout" => timeout}
        },
        %{
          "id" => "email_1",
          "type" => "send_email",
          "position" => %{"x" => 200, "y" => 0},
          "config" => %{"template_id" => "followup"}
        },
        %{
          "id" => "exit_1",
          "type" => "exit",
          "position" => %{"x" => 300, "y" => 0},
          "config" => %{}
        }
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
        %{
          "id" => "e2",
          "source" => "wait_1",
          "target" => "email_1",
          "branch" => "event_received"
        },
        %{"id" => "e3", "source" => "wait_1", "target" => "exit_1", "branch" => "timed_out"},
        %{"id" => "e4", "source" => "email_1", "target" => "exit_1"}
      ]
    }
  end

  test "migrate_all updates waiting instances and event routing works on new version",
       %{conn: conn} do
    # Step 1: Create flow with v1
    conn_create = post(conn, "/api/v1/flows", %{"name" => "Migration E2E"})
    %{"data" => %{"id" => flow_id}} = json_response(conn_create, 201)

    post(conn, "/api/v1/flows/#{flow_id}/versions", %{
      "graph" => wait_graph("email_opened"),
      "changelog" => "v1"
    })

    post(conn, "/api/v1/flows/#{flow_id}/activate")

    # Step 2: Trigger 2 customers — both reach waiting
    cust1 = "mig_e2e_1_#{System.unique_integer([:positive])}"
    cust2 = "mig_e2e_2_#{System.unique_integer([:positive])}"

    %{"instance_id" => id1} =
      json_response(post(conn, "/api/v1/flows/#{flow_id}/trigger", %{"customer_id" => cust1}), 201)

    %{"instance_id" => id2} =
      json_response(post(conn, "/api/v1/flows/#{flow_id}/trigger", %{"customer_id" => cust2}), 201)

    Process.sleep(200)

    assert FlowServer.get_state(id1).status == :waiting
    assert FlowServer.get_state(id2).status == :waiting

    # Step 3: Create v2 with different event_type
    post(conn, "/api/v1/flows/#{flow_id}/versions", %{
      "graph" => wait_graph("push_opened"),
      "changelog" => "v2"
    })

    # Step 4: Migrate
    conn_migrate =
      post(conn, "/api/v1/flows/#{flow_id}/versions/2/migrate", %{"strategy" => "migrate_all"})

    body = json_response(conn_migrate, 200)
    assert id1 in body["data"]["migrated"]
    assert id2 in body["data"]["migrated"]

    # Step 5: Verify FlowServer states updated
    assert FlowServer.get_state(id1).version_number == 2
    assert FlowServer.get_state(id1).context["_waiting_event_type"] == "push_opened"
    assert FlowServer.get_state(id2).version_number == 2

    # Step 6: DB verification
    db1 = Kalcifer.Repo.get!(FlowInstance, id1)
    assert db1.version_number == 2
    assert db1.migrated_from_version == 1
    assert db1.migrated_at != nil

    # Step 7: Send new event type — flow completes on v2
    pid1 = GenServer.whereis({:via, Registry, {Kalcifer.Engine.ProcessRegistry, id1}})
    ref1 = Process.monitor(pid1)

    post(conn, "/api/v1/events", %{
      "customer_id" => cust1,
      "event_type" => "push_opened",
      "data" => %{}
    })

    receive do
      {:DOWN, ^ref1, :process, ^pid1, :normal} -> :ok
    after
      3000 -> flunk("FlowServer did not complete after migrated event")
    end

    assert Kalcifer.Repo.get!(FlowInstance, id1).status == "completed"

    # Clean up second instance
    GenServer.stop({:via, Registry, {Kalcifer.Engine.ProcessRegistry, id2}}, :normal)
  end

  test "removed node exits instance gracefully", %{conn: conn} do
    conn_create = post(conn, "/api/v1/flows", %{"name" => "Removed Node E2E"})
    %{"data" => %{"id" => flow_id}} = json_response(conn_create, 201)

    post(conn, "/api/v1/flows/#{flow_id}/versions", %{
      "graph" => wait_graph("email_opened"),
      "changelog" => "v1"
    })

    post(conn, "/api/v1/flows/#{flow_id}/activate")

    customer_id = "removed_node_cust_#{System.unique_integer([:positive])}"

    %{"instance_id" => instance_id} =
      json_response(
        post(conn, "/api/v1/flows/#{flow_id}/trigger", %{"customer_id" => customer_id}),
        201
      )

    Process.sleep(200)
    assert FlowServer.get_state(instance_id).status == :waiting

    # v2 removes wait_1 node entirely
    simple_graph = %{
      "nodes" => [
        %{
          "id" => "entry_1",
          "type" => "event_entry",
          "position" => %{"x" => 0, "y" => 0},
          "config" => %{"event_type" => "signed_up"}
        },
        %{
          "id" => "exit_1",
          "type" => "exit",
          "position" => %{"x" => 200, "y" => 0},
          "config" => %{}
        }
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "exit_1"}
      ]
    }

    post(conn, "/api/v1/flows/#{flow_id}/versions", %{
      "graph" => simple_graph,
      "changelog" => "v2 removes wait"
    })

    conn_migrate =
      post(conn, "/api/v1/flows/#{flow_id}/versions/2/migrate", %{"strategy" => "migrate_all"})

    body = json_response(conn_migrate, 200)
    assert instance_id in body["data"]["exited"]

    # Verify DB
    db_instance = Kalcifer.Repo.get!(FlowInstance, instance_id)
    assert db_instance.status == "exited"
    assert db_instance.exit_reason == "node_removed_in_new_version"
  end

  test "rollback restores previous version behavior", %{conn: conn} do
    conn_create = post(conn, "/api/v1/flows", %{"name" => "Rollback E2E"})
    %{"data" => %{"id" => flow_id}} = json_response(conn_create, 201)

    post(conn, "/api/v1/flows/#{flow_id}/versions", %{
      "graph" => wait_graph("email_opened"),
      "changelog" => "v1"
    })

    post(conn, "/api/v1/flows/#{flow_id}/activate")

    customer_id = "rollback_cust_#{System.unique_integer([:positive])}"

    %{"instance_id" => instance_id} =
      json_response(
        post(conn, "/api/v1/flows/#{flow_id}/trigger", %{"customer_id" => customer_id}),
        201
      )

    Process.sleep(200)
    assert FlowServer.get_state(instance_id).status == :waiting

    # Migrate to v2
    post(conn, "/api/v1/flows/#{flow_id}/versions", %{
      "graph" => wait_graph("push_opened"),
      "changelog" => "v2"
    })

    post(conn, "/api/v1/flows/#{flow_id}/versions/2/migrate", %{"strategy" => "migrate_all"})
    assert FlowServer.get_state(instance_id).version_number == 2

    # Rollback to v1
    conn_rollback = post(conn, "/api/v1/flows/#{flow_id}/versions/1/rollback")
    body = json_response(conn_rollback, 200)
    assert instance_id in body["data"]["migrated"]

    state = FlowServer.get_state(instance_id)
    assert state.version_number == 1
    assert state.context["_waiting_event_type"] == "email_opened"

    # Send v1 event — flow should complete
    pid = GenServer.whereis({:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}})
    ref = Process.monitor(pid)

    post(conn, "/api/v1/events", %{
      "customer_id" => customer_id,
      "event_type" => "email_opened",
      "data" => %{}
    })

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
    after
      3000 -> flunk("FlowServer did not complete after rollback event")
    end

    assert Kalcifer.Repo.get!(FlowInstance, instance_id).status == "completed"
  end

  test "new_entries_only leaves existing instances on old version", %{conn: conn} do
    conn_create = post(conn, "/api/v1/flows", %{"name" => "NewEntries E2E"})
    %{"data" => %{"id" => flow_id}} = json_response(conn_create, 201)

    post(conn, "/api/v1/flows/#{flow_id}/versions", %{
      "graph" => wait_graph("email_opened"),
      "changelog" => "v1"
    })

    post(conn, "/api/v1/flows/#{flow_id}/activate")

    old_cust = "old_cust_#{System.unique_integer([:positive])}"

    %{"instance_id" => old_id} =
      json_response(
        post(conn, "/api/v1/flows/#{flow_id}/trigger", %{"customer_id" => old_cust}),
        201
      )

    Process.sleep(200)
    assert FlowServer.get_state(old_id).status == :waiting

    # Create v2 and migrate with new_entries_only
    post(conn, "/api/v1/flows/#{flow_id}/versions", %{
      "graph" => wait_graph("push_opened"),
      "changelog" => "v2"
    })

    post(conn, "/api/v1/flows/#{flow_id}/versions/2/migrate", %{
      "strategy" => "new_entries_only"
    })

    # Old instance stays on v1
    assert FlowServer.get_state(old_id).version_number == 1
    assert FlowServer.get_state(old_id).context["_waiting_event_type"] == "email_opened"

    # New trigger uses v2
    new_cust = "new_cust_#{System.unique_integer([:positive])}"

    %{"instance_id" => new_id} =
      json_response(
        post(conn, "/api/v1/flows/#{flow_id}/trigger", %{"customer_id" => new_cust}),
        201
      )

    Process.sleep(200)

    state = FlowServer.get_state(new_id)
    assert state.version_number == 2
    assert state.context["_waiting_event_type"] == "push_opened"

    # Old instance still responds to v1 event
    pid = GenServer.whereis({:via, Registry, {Kalcifer.Engine.ProcessRegistry, old_id}})
    ref = Process.monitor(pid)

    post(conn, "/api/v1/events", %{
      "customer_id" => old_cust,
      "event_type" => "email_opened",
      "data" => %{}
    })

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
    after
      3000 -> flunk("Old instance did not complete on v1 event")
    end

    assert Kalcifer.Repo.get!(FlowInstance, old_id).status == "completed"

    # Clean up new instance
    GenServer.stop({:via, Registry, {Kalcifer.Engine.ProcessRegistry, new_id}}, :normal)
  end
end
