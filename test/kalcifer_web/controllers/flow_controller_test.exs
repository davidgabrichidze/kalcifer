defmodule KalciferWeb.FlowControllerTest do
  use KalciferWeb.ConnCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Tenants

  @raw_api_key "test_key_for_flow_controller"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  describe "index" do
    test "lists flows for tenant", %{conn: conn, tenant: tenant} do
      insert(:flow, tenant: tenant, name: "Flow A")
      insert(:flow, tenant: tenant, name: "Flow B")

      conn = get(conn, "/api/v1/flows")
      body = json_response(conn, 200)

      assert length(body["data"]) == 2
    end

    test "does not list other tenant's flows", %{conn: conn} do
      other_tenant = insert(:tenant)
      insert(:flow, tenant: other_tenant, name: "Secret Flow")

      conn = get(conn, "/api/v1/flows")
      body = json_response(conn, 200)

      assert body["data"] == []
    end

    test "filters by status", %{conn: conn, tenant: tenant} do
      insert(:flow, tenant: tenant, status: "draft")
      insert(:flow, tenant: tenant, status: "active")

      conn = get(conn, "/api/v1/flows?status=active")
      body = json_response(conn, 200)

      assert length(body["data"]) == 1
      assert hd(body["data"])["status"] == "active"
    end
  end

  describe "create" do
    test "creates a flow", %{conn: conn} do
      conn =
        post(conn, "/api/v1/flows", %{
          "name" => "Welcome Flow",
          "description" => "Onboarding"
        })

      body = json_response(conn, 201)
      assert body["data"]["name"] == "Welcome Flow"
      assert body["data"]["description"] == "Onboarding"
      assert body["data"]["status"] == "draft"
      assert body["data"]["id"]
    end

    test "returns error for missing name", %{conn: conn} do
      conn = post(conn, "/api/v1/flows", %{})

      assert json_response(conn, 422)["errors"]["name"]
    end
  end

  describe "show" do
    test "returns a flow", %{conn: conn, tenant: tenant} do
      flow = insert(:flow, tenant: tenant, name: "My Flow")

      conn = get(conn, "/api/v1/flows/#{flow.id}")
      body = json_response(conn, 200)

      assert body["data"]["id"] == flow.id
      assert body["data"]["name"] == "My Flow"
    end

    test "returns 404 for other tenant's flow", %{conn: conn} do
      other_tenant = insert(:tenant)
      flow = insert(:flow, tenant: other_tenant)

      conn = get(conn, "/api/v1/flows/#{flow.id}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "returns 404 for non-existent flow", %{conn: conn} do
      conn = get(conn, "/api/v1/flows/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "update" do
    test "updates a draft flow", %{conn: conn, tenant: tenant} do
      flow = insert(:flow, tenant: tenant, name: "Old Name")

      conn = put(conn, "/api/v1/flows/#{flow.id}", %{"name" => "New Name"})
      body = json_response(conn, 200)

      assert body["data"]["name"] == "New Name"
    end

    test "rejects update of non-draft flow", %{conn: conn, tenant: tenant} do
      flow = insert(:flow, tenant: tenant, status: "active")

      conn = put(conn, "/api/v1/flows/#{flow.id}", %{"name" => "Updated"})
      assert json_response(conn, 422) == %{"error" => "flow_not_draft"}
    end

    test "returns 404 for other tenant's flow", %{conn: conn} do
      other_tenant = insert(:tenant)
      flow = insert(:flow, tenant: other_tenant)

      conn = put(conn, "/api/v1/flows/#{flow.id}", %{"name" => "Hacked"})
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "delete" do
    test "deletes a draft flow", %{conn: conn, tenant: tenant} do
      flow = insert(:flow, tenant: tenant)

      conn = delete(conn, "/api/v1/flows/#{flow.id}")
      assert response(conn, 204)
    end

    test "rejects delete of non-draft flow", %{conn: conn, tenant: tenant} do
      flow = insert(:flow, tenant: tenant, status: "active")

      conn = delete(conn, "/api/v1/flows/#{flow.id}")
      assert json_response(conn, 422) == %{"error" => "flow_not_draft"}
    end
  end

  describe "activate" do
    test "activates a flow with a draft version", %{conn: conn, tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, graph: valid_graph())

      conn = post(conn, "/api/v1/flows/#{flow.id}/activate")
      body = json_response(conn, 200)

      assert body["data"]["status"] == "active"
      assert body["data"]["active_version_id"]
    end

    test "rejects activation without draft version", %{conn: conn, tenant: tenant} do
      flow = insert(:flow, tenant: tenant)

      conn = post(conn, "/api/v1/flows/#{flow.id}/activate")
      assert json_response(conn, 422) == %{"error" => "no_draft_version"}
    end
  end

  describe "pause" do
    test "pauses an active flow", %{conn: conn, tenant: tenant} do
      flow = insert(:flow, tenant: tenant, status: "active")

      conn = post(conn, "/api/v1/flows/#{flow.id}/pause")
      body = json_response(conn, 200)

      assert body["data"]["status"] == "paused"
    end
  end

  describe "archive" do
    test "archives an active flow", %{conn: conn, tenant: tenant} do
      flow = insert(:flow, tenant: tenant, status: "active")

      conn = post(conn, "/api/v1/flows/#{flow.id}/archive")
      body = json_response(conn, 200)

      assert body["data"]["status"] == "archived"
    end
  end
end
