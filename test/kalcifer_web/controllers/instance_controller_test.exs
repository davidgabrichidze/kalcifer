defmodule KalciferWeb.InstanceControllerTest do
  use KalciferWeb.ConnCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Tenants

  @raw_api_key "test_key_for_instance_controller"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  describe "GET /api/v1/flows/:flow_id/instances" do
    test "lists instances for a flow", %{conn: conn, tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_instance, flow: flow, tenant: tenant, status: "running")
      insert(:flow_instance, flow: flow, tenant: tenant, status: "completed")

      conn = get(conn, "/api/v1/flows/#{flow.id}/instances")

      assert json_response(conn, 200)["data"] |> length() == 2
    end

    test "filters by status", %{conn: conn, tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_instance, flow: flow, tenant: tenant, status: "running")
      insert(:flow_instance, flow: flow, tenant: tenant, status: "completed")

      conn = get(conn, "/api/v1/flows/#{flow.id}/instances?status=running")

      data = json_response(conn, 200)["data"]
      assert length(data) == 1
      assert hd(data)["status"] == "running"
    end
  end

  describe "GET /api/v1/instances/:id" do
    test "returns instance with steps", %{conn: conn, tenant: tenant} do
      instance = insert(:flow_instance, tenant: tenant)
      insert(:execution_step, instance: instance, node_id: "entry_1")

      conn = get(conn, "/api/v1/instances/#{instance.id}")

      body = json_response(conn, 200)
      assert body["data"]["id"] == instance.id
      assert length(body["steps"]) == 1
    end

    test "returns 404 for other tenant's instance", %{conn: conn} do
      other_tenant = insert(:tenant)
      instance = insert(:flow_instance, tenant: other_tenant)

      conn = get(conn, "/api/v1/instances/#{instance.id}")

      assert json_response(conn, 404)
    end
  end

  describe "GET /api/v1/instances/:id/timeline" do
    test "returns chronological step history", %{conn: conn, tenant: tenant} do
      instance = insert(:flow_instance, tenant: tenant)
      insert(:execution_step, instance: instance, node_id: "entry_1")
      insert(:execution_step, instance: instance, node_id: "action_1")

      conn = get(conn, "/api/v1/instances/#{instance.id}/timeline")

      body = json_response(conn, 200)
      assert length(body["data"]) == 2
    end
  end

  describe "POST /api/v1/instances/:id/cancel" do
    test "cancels a running instance", %{conn: conn, tenant: tenant} do
      instance = insert(:flow_instance, tenant: tenant, status: "running")

      conn = post(conn, "/api/v1/instances/#{instance.id}/cancel")

      body = json_response(conn, 200)
      assert body["data"]["status"] == "exited"
      assert body["data"]["exit_reason"] == "cancelled_by_operator"
    end

    test "cancels a waiting instance", %{conn: conn, tenant: tenant} do
      instance = insert(:flow_instance, tenant: tenant, status: "waiting")

      conn = post(conn, "/api/v1/instances/#{instance.id}/cancel")

      body = json_response(conn, 200)
      assert body["data"]["status"] == "exited"
    end

    test "returns 409 for completed instance", %{conn: conn, tenant: tenant} do
      instance =
        insert(:flow_instance,
          tenant: tenant,
          status: "completed",
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      conn = post(conn, "/api/v1/instances/#{instance.id}/cancel")

      assert json_response(conn, 409)
    end
  end
end
