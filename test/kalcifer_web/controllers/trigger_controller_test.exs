defmodule KalciferWeb.TriggerControllerTest do
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Flows
  alias Kalcifer.Tenants

  @raw_api_key "test_key_for_trigger_controller"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  test "triggers flow for customer", %{conn: conn, tenant: tenant} do
    flow = insert(:flow, tenant: tenant)
    insert(:flow_version, flow: flow, graph: valid_graph())
    {:ok, flow} = Flows.activate_flow(flow)

    conn =
      post(conn, "/api/v1/flows/#{flow.id}/trigger", %{
        "customer_id" => "cust_123",
        "context" => %{"source" => "signup"}
      })

    body = json_response(conn, 201)
    assert body["instance_id"]

    # Give the FlowServer time to start and execute
    Process.sleep(100)

    instance = Kalcifer.Repo.get(Kalcifer.Flows.FlowInstance, body["instance_id"])
    assert instance
    assert instance.customer_id == "cust_123"
  end

  test "rejects trigger for other tenant's flow", %{conn: conn} do
    other_tenant = insert(:tenant)
    flow = insert(:flow, tenant: other_tenant)
    insert(:flow_version, flow: flow, graph: valid_graph())
    {:ok, _flow} = Flows.activate_flow(flow)

    conn =
      post(conn, "/api/v1/flows/#{flow.id}/trigger", %{
        "customer_id" => "cust_123"
      })

    assert json_response(conn, 404) == %{"error" => "not_found"}
  end

  test "rejects trigger for non-active flow", %{conn: conn, tenant: tenant} do
    flow = insert(:flow, tenant: tenant, status: "draft")

    conn =
      post(conn, "/api/v1/flows/#{flow.id}/trigger", %{
        "customer_id" => "cust_123"
      })

    assert json_response(conn, 422) == %{"error" => "flow_not_active"}
  end

  test "rejects trigger for paused flow", %{conn: conn, tenant: tenant} do
    flow = insert(:flow, tenant: tenant, status: "paused")

    conn =
      post(conn, "/api/v1/flows/#{flow.id}/trigger", %{
        "customer_id" => "cust_123"
      })

    assert json_response(conn, 422) == %{"error" => "flow_not_active"}
  end

  test "returns 409 when customer already in flow", %{conn: conn, tenant: tenant} do
    flow = insert(:flow, tenant: tenant)
    insert(:flow_version, flow: flow, graph: valid_graph())
    {:ok, flow} = Flows.activate_flow(flow)

    insert(:flow_instance,
      flow: flow,
      tenant: tenant,
      customer_id: "cust_dedup",
      status: "running"
    )

    conn =
      post(conn, "/api/v1/flows/#{flow.id}/trigger", %{
        "customer_id" => "cust_dedup"
      })

    assert json_response(conn, 409) == %{"error" => "already_in_flow"}
  end

  test "returns 429 when customer exceeds frequency cap", %{conn: conn, tenant: tenant} do
    flow =
      insert(:flow,
        tenant: tenant,
        frequency_cap: %{"max_messages" => 1, "time_window" => "24h", "channel" => "email"}
      )

    insert(:flow_version, flow: flow, graph: valid_graph())
    {:ok, flow} = Flows.activate_flow(flow)

    instance =
      insert(:flow_instance,
        flow: flow,
        tenant: tenant,
        customer_id: "cust_capped",
        status: "completed"
      )

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    insert(:execution_step,
      instance: instance,
      node_type: "send_email",
      status: "completed",
      completed_at: now
    )

    conn =
      post(conn, "/api/v1/flows/#{flow.id}/trigger", %{
        "customer_id" => "cust_capped"
      })

    assert json_response(conn, 429) == %{"error" => "frequency_cap_exceeded"}
  end

  test "trigger passes initial context to instance", %{conn: conn, tenant: tenant} do
    flow = insert(:flow, tenant: tenant)
    insert(:flow_version, flow: flow, graph: valid_graph())
    {:ok, flow} = Kalcifer.Flows.activate_flow(flow)

    conn =
      post(conn, "/api/v1/flows/#{flow.id}/trigger", %{
        "customer_id" => "cust_ctx",
        "context" => %{"source" => "api", "campaign" => "summer"}
      })

    body = json_response(conn, 201)
    instance_id = body["instance_id"]

    Process.sleep(200)

    instance = Kalcifer.Repo.get(Kalcifer.Flows.FlowInstance, instance_id)
    assert instance
    assert instance.customer_id == "cust_ctx"
  end
end
