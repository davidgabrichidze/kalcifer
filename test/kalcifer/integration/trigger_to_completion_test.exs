defmodule Kalcifer.Integration.TriggerToCompletionTest do
  @moduledoc """
  End-to-end integration test: create flow via API → trigger → wait_for_event → send event → complete.
  """
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Tenants

  @raw_api_key "integration_test_api_key"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  test "full API path: create flow → add version → activate → trigger → wait → event → complete",
       %{conn: conn} do
    # Step 1: Create flow
    conn_create = post(conn, "/api/v1/flows", %{"name" => "E2E Integration Flow"})
    assert %{"data" => %{"id" => flow_id}} = json_response(conn_create, 201)

    # Step 2: Add a version with branching wait_for_event graph
    graph = %{
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
          "config" => %{"event_type" => "email_opened", "timeout" => "3d"}
        },
        %{
          "id" => "email_1",
          "type" => "send_email",
          "position" => %{"x" => 200, "y" => 0},
          "config" => %{"template_id" => "followup"}
        },
        %{
          "id" => "sms_1",
          "type" => "send_sms",
          "position" => %{"x" => 200, "y" => 100},
          "config" => %{"template_id" => "reminder"}
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
        %{"id" => "e3", "source" => "wait_1", "target" => "sms_1", "branch" => "timed_out"},
        %{"id" => "e4", "source" => "email_1", "target" => "exit_1"},
        %{"id" => "e5", "source" => "sms_1", "target" => "exit_1"}
      ]
    }

    conn_version =
      post(conn, "/api/v1/flows/#{flow_id}/versions", %{
        "graph" => graph,
        "changelog" => "E2E test version"
      })

    assert %{"data" => %{"version_number" => 1}} = json_response(conn_version, 201)

    # Step 3: Activate
    conn_activate = post(conn, "/api/v1/flows/#{flow_id}/activate")
    assert %{"data" => %{"status" => "active"}} = json_response(conn_activate, 200)

    # Step 4: Trigger flow for a customer
    customer_id = "e2e_customer_#{System.unique_integer([:positive])}"

    conn_trigger =
      post(conn, "/api/v1/flows/#{flow_id}/trigger", %{
        "customer_id" => customer_id,
        "context" => %{"source" => "integration_test"}
      })

    assert %{"instance_id" => instance_id} = json_response(conn_trigger, 201)

    # Step 5: Verify instance is waiting
    Process.sleep(200)

    via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}
    pid = GenServer.whereis(via)
    assert pid, "FlowServer should be alive and waiting"

    state = FlowServer.get_state(instance_id)
    assert state.status == :waiting
    assert state.waiting_node_id == "wait_1"

    # Step 6: Send event that matches the wait_for_event node
    ref = Process.monitor(pid)

    conn_event =
      post(conn, "/api/v1/events", %{
        "customer_id" => customer_id,
        "event_type" => "email_opened",
        "data" => %{"email_id" => "test_email_123"}
      })

    assert %{"routed" => 1} = json_response(conn_event, 202)

    # Step 7: Wait for flow to complete
    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
    after
      3000 -> flunk("FlowServer did not complete after event")
    end

    # Step 8: Verify final state
    instance = Kalcifer.Repo.get!(FlowInstance, instance_id)
    assert instance.status == "completed"

    # Verify event_received branch was taken (email_1), not timed_out (sms_1)
    steps = Kalcifer.Repo.all(Kalcifer.Flows.ExecutionStep)
    instance_steps = Enum.filter(steps, &(&1.instance_id == instance_id))
    node_ids = Enum.map(instance_steps, & &1.node_id)

    assert "entry_1" in node_ids
    assert "wait_1" in node_ids
    assert "email_1" in node_ids
    assert "exit_1" in node_ids
    refute "sms_1" in node_ids
  end
end
