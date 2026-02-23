defmodule KalciferWeb.MigrationControllerTest do
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Flows
  alias Kalcifer.Tenants

  @raw_api_key "test_key_for_migration_controller"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  defp wait_graph(event_type \\ "email_opened") do
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
          "config" => %{"event_type" => event_type, "timeout" => "3d"}
        },
        %{
          "id" => "exit_1",
          "type" => "exit",
          "position" => %{"x" => 200, "y" => 0},
          "config" => %{}
        }
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
        %{
          "id" => "e2",
          "source" => "wait_1",
          "target" => "exit_1",
          "branch" => "event_received"
        },
        %{"id" => "e3", "source" => "wait_1", "target" => "exit_1", "branch" => "timed_out"}
      ]
    }
  end

  defp setup_flow_with_waiting_instance(conn, tenant) do
    flow = insert(:flow, tenant: tenant)
    insert(:flow_version, flow: flow, version_number: 1, graph: wait_graph())
    {:ok, flow} = Flows.activate_flow(flow)

    customer_id = "mig_cust_#{System.unique_integer([:positive])}"

    conn_trigger =
      post(conn, "/api/v1/flows/#{flow.id}/trigger", %{"customer_id" => customer_id})

    %{"instance_id" => instance_id} = json_response(conn_trigger, 201)
    Process.sleep(200)

    state = FlowServer.get_state(instance_id)
    assert state.status == :waiting

    %{flow: Flows.get_flow!(flow.id), instance_id: instance_id, customer_id: customer_id}
  end

  test "migrate with migrate_all migrates waiting instances", %{conn: conn, tenant: tenant} do
    %{flow: flow, instance_id: instance_id} =
      setup_flow_with_waiting_instance(conn, tenant)

    {:ok, _v2} = Flows.create_version(flow, %{graph: wait_graph("push_opened"), changelog: "v2"})

    conn_migrate =
      post(conn, "/api/v1/flows/#{flow.id}/versions/2/migrate", %{"strategy" => "migrate_all"})

    body = json_response(conn_migrate, 200)
    assert instance_id in body["data"]["migrated"]

    state = FlowServer.get_state(instance_id)
    assert state.version_number == 2

    GenServer.stop({:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}, :normal)
  end

  test "migrate with new_entries_only skips instances", %{conn: conn, tenant: tenant} do
    %{flow: flow, instance_id: instance_id} =
      setup_flow_with_waiting_instance(conn, tenant)

    {:ok, _v2} = Flows.create_version(flow, %{graph: wait_graph("push_opened"), changelog: "v2"})

    conn_migrate =
      post(conn, "/api/v1/flows/#{flow.id}/versions/2/migrate", %{
        "strategy" => "new_entries_only"
      })

    body = json_response(conn_migrate, 200)
    assert instance_id in body["data"]["skipped"]

    state = FlowServer.get_state(instance_id)
    assert state.version_number == 1

    GenServer.stop({:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}, :normal)
  end

  test "rollback restores previous version", %{conn: conn, tenant: tenant} do
    %{flow: flow, instance_id: instance_id} =
      setup_flow_with_waiting_instance(conn, tenant)

    {:ok, _v2} = Flows.create_version(flow, %{graph: wait_graph("push_opened"), changelog: "v2"})

    # Migrate to v2
    post(conn, "/api/v1/flows/#{flow.id}/versions/2/migrate", %{"strategy" => "migrate_all"})

    state = FlowServer.get_state(instance_id)
    assert state.version_number == 2

    # Rollback to v1
    conn_rollback = post(conn, "/api/v1/flows/#{flow.id}/versions/1/rollback")
    body = json_response(conn_rollback, 200)
    assert instance_id in body["data"]["migrated"]

    state = FlowServer.get_state(instance_id)
    assert state.version_number == 1

    GenServer.stop({:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}, :normal)
  end

  test "migration_status returns instance counts per version", %{conn: conn, tenant: tenant} do
    %{flow: flow, instance_id: instance_id} =
      setup_flow_with_waiting_instance(conn, tenant)

    conn_status = get(conn, "/api/v1/flows/#{flow.id}/migration_status")
    body = json_response(conn_status, 200)

    # version 1 should have 1 waiting instance
    assert body["data"]["1"] == 1

    GenServer.stop({:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}, :normal)
  end

  test "migrate returns 404 for non-existent flow", %{conn: conn} do
    conn_migrate =
      post(conn, "/api/v1/flows/#{Ecto.UUID.generate()}/versions/1/migrate", %{
        "strategy" => "migrate_all"
      })

    assert json_response(conn_migrate, 404) == %{"error" => "not_found"}
  end

  test "migrate returns 404 for non-existent version", %{conn: conn, tenant: tenant} do
    flow = insert(:flow, tenant: tenant)
    insert(:flow_version, flow: flow, version_number: 1, graph: wait_graph())
    {:ok, _flow} = Flows.activate_flow(flow)

    conn_migrate =
      post(conn, "/api/v1/flows/#{flow.id}/versions/99/migrate", %{
        "strategy" => "migrate_all"
      })

    assert json_response(conn_migrate, 404) == %{"error" => "version_not_found"}
  end

  test "rollback returns 404 for other tenant's flow", %{conn: conn} do
    other_tenant = insert(:tenant)
    flow = insert(:flow, tenant: other_tenant)

    conn_rollback = post(conn, "/api/v1/flows/#{flow.id}/versions/1/rollback")
    assert json_response(conn_rollback, 404) == %{"error" => "not_found"}
  end

  # --- Edge cases ---

  test "migrate with invalid version number string returns 422", %{conn: conn, tenant: tenant} do
    flow = insert(:flow, tenant: tenant)

    conn_resp =
      post(conn, "/api/v1/flows/#{flow.id}/versions/abc/migrate", %{"strategy" => "migrate_all"})

    assert json_response(conn_resp, 422) == %{"error" => "invalid_version_number"}
  end

  test "rollback with invalid version number string returns 422", %{conn: conn, tenant: tenant} do
    flow = insert(:flow, tenant: tenant)

    conn_resp = post(conn, "/api/v1/flows/#{flow.id}/versions/xyz/rollback")
    assert json_response(conn_resp, 422) == %{"error" => "invalid_version_number"}
  end

  test "migrate defaults to new_entries_only strategy", %{conn: conn, tenant: tenant} do
    %{flow: flow, instance_id: instance_id} =
      setup_flow_with_waiting_instance(conn, tenant)

    {:ok, _v2} = Flows.create_version(flow, %{graph: wait_graph("push_opened"), changelog: "v2"})

    # No strategy param — should default to new_entries_only
    conn_migrate = post(conn, "/api/v1/flows/#{flow.id}/versions/2/migrate", %{})

    body = json_response(conn_migrate, 200)
    assert instance_id in body["data"]["skipped"]

    GenServer.stop({:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}, :normal)
  end

  test "rollback returns 422 when flow has no active version", %{conn: conn, tenant: tenant} do
    flow = insert(:flow, tenant: tenant, status: "draft")

    conn_resp = post(conn, "/api/v1/flows/#{flow.id}/versions/1/rollback")
    assert json_response(conn_resp, 422) == %{"error" => "no_active_version"}
  end

  test "migrate returns 422 when flow has no active version", %{conn: conn, tenant: tenant} do
    flow = insert(:flow, tenant: tenant, status: "draft")
    insert(:flow_version, flow: flow, version_number: 1, graph: wait_graph())

    conn_resp =
      post(conn, "/api/v1/flows/#{flow.id}/versions/1/migrate", %{"strategy" => "migrate_all"})

    assert json_response(conn_resp, 422) == %{"error" => "no_active_version"}
  end

  test "migration_status returns empty map for flow with no instances", %{
    conn: conn,
    tenant: tenant
  } do
    flow = insert(:flow, tenant: tenant)

    conn_resp = get(conn, "/api/v1/flows/#{flow.id}/migration_status")
    body = json_response(conn_resp, 200)
    assert body["data"] == %{}
  end

  test "migrate returns 404 for status of other tenant's flow", %{conn: conn} do
    other_tenant = insert(:tenant)
    flow = insert(:flow, tenant: other_tenant)

    conn_resp = get(conn, "/api/v1/flows/#{flow.id}/migration_status")
    assert json_response(conn_resp, 404) == %{"error" => "not_found"}
  end
end
