defmodule Kalcifer.Bugs.CrossTenantEventTest do
  @moduledoc """
  C1: Regression test for cross-tenant event isolation.
  EventRouter.route_event filters by tenant_id, preventing Tenant A from
  resuming Tenant B's waiting flow instances.
  """
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Tenants

  @tenant_a_key "tenant_a_event_key"
  @tenant_b_key "tenant_b_event_key"

  defp wait_graph do
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
          "config" => %{"event_type" => "email_opened", "timeout" => "3d"}
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

  test "tenant A should NOT be able to resume tenant B's waiting instance via events" do
    # Setup Tenant B with a waiting flow instance
    hash_b = Tenants.hash_api_key(@tenant_b_key)
    tenant_b = insert(:tenant, api_key_hash: hash_b)

    flow_b = insert(:flow, tenant: tenant_b)
    graph = wait_graph()
    shared_customer_id = "shared_customer_#{System.unique_integer([:positive])}"

    args = %{
      instance_id: Ecto.UUID.generate(),
      flow_id: flow_b.id,
      version_number: 1,
      customer_id: shared_customer_id,
      tenant_id: tenant_b.id,
      graph: graph
    }

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        Kalcifer.Engine.FlowSupervisor,
        {FlowServer, args}
      )

    Process.sleep(200)
    assert FlowServer.get_state(args.instance_id).status == :waiting

    # Tenant A sends an event for the same customer_id
    hash_a = Tenants.hash_api_key(@tenant_a_key)
    _tenant_a = insert(:tenant, api_key_hash: hash_a)

    conn_a =
      build_conn()
      |> put_req_header("authorization", "Bearer #{@tenant_a_key}")
      |> put_req_header("content-type", "application/json")

    conn_resp =
      post(conn_a, "/api/v1/events", %{
        "customer_id" => shared_customer_id,
        "event_type" => "email_opened",
        "data" => %{}
      })

    body = json_response(conn_resp, 202)

    assert body["routed"] == 0,
           "Tenant A routed #{body["routed"]} event(s) to Tenant B's instance!"
  end
end
