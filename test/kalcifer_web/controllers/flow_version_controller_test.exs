defmodule KalciferWeb.FlowVersionControllerTest do
  use KalciferWeb.ConnCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Tenants

  @raw_api_key "test_key_for_version_controller"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)
    flow = insert(:flow, tenant: tenant)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant, flow: flow}
  end

  describe "index" do
    test "lists versions for a flow", %{conn: conn, flow: flow} do
      insert(:flow_version, flow: flow, version_number: 1)
      insert(:flow_version, flow: flow, version_number: 2)

      conn = get(conn, "/api/v1/flows/#{flow.id}/versions")
      body = json_response(conn, 200)

      assert length(body["data"]) == 2
    end

    test "returns 404 for other tenant's flow", %{conn: conn} do
      other_tenant = insert(:tenant)
      other_flow = insert(:flow, tenant: other_tenant)

      conn = get(conn, "/api/v1/flows/#{other_flow.id}/versions")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "create" do
    test "creates a version", %{conn: conn, flow: flow} do
      graph = valid_graph()

      conn =
        post(conn, "/api/v1/flows/#{flow.id}/versions", %{
          "graph" => graph,
          "changelog" => "Added entry node"
        })

      body = json_response(conn, 201)
      assert body["data"]["version_number"] == 1
      assert body["data"]["graph"] == graph
      assert body["data"]["status"] == "draft"
    end
  end

  describe "show" do
    test "returns a specific version", %{conn: conn, flow: flow} do
      insert(:flow_version, flow: flow, version_number: 1, changelog: "First")

      conn = get(conn, "/api/v1/flows/#{flow.id}/versions/1")
      body = json_response(conn, 200)

      assert body["data"]["version_number"] == 1
      assert body["data"]["changelog"] == "First"
    end

    test "returns 404 for non-existent version", %{conn: conn, flow: flow} do
      conn = get(conn, "/api/v1/flows/#{flow.id}/versions/999")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end
end
