defmodule KalciferWeb.EventControllerTest do
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Tenants

  @raw_api_key "test_key_for_event_controller"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  test "routes event to waiting instance", %{conn: conn, tenant: tenant} do
    flow = insert(:flow, tenant: tenant)
    graph = branching_graph()
    customer_id = "event_test_customer"

    args = %{
      instance_id: Ecto.UUID.generate(),
      flow_id: flow.id,
      version_number: 1,
      customer_id: customer_id,
      tenant_id: tenant.id,
      graph: graph
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Kalcifer.Engine.FlowSupervisor,
        {FlowServer, args}
      )

    # Wait for server to reach waiting state
    Process.sleep(100)
    assert %{status: :waiting} = FlowServer.get_state(args.instance_id)

    # Send event via HTTP
    conn =
      post(conn, "/api/v1/events", %{
        "customer_id" => customer_id,
        "event_type" => "email_opened",
        "data" => %{"email_id" => "abc"}
      })

    body = json_response(conn, 202)
    assert body["routed"] == 1

    # Wait for flow to complete after event
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
    after
      2000 -> flunk("FlowServer did not complete after event")
    end
  end

  test "returns empty when no matching instances", %{conn: conn} do
    conn =
      post(conn, "/api/v1/events", %{
        "customer_id" => "nobody",
        "event_type" => "some_event",
        "data" => %{}
      })

    body = json_response(conn, 202)
    assert body["routed"] == 0
  end
end
