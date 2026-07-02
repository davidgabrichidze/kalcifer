defmodule KalciferWeb.AnalyticsControllerTest do
  use KalciferWeb.ConnCase, async: true

  import Kalcifer.Factory

  setup do
    # No x-tenant-id header → TenantResolver falls back to "Demo Tenant"
    demo = insert(:tenant, name: "Demo Tenant")
    %{demo: demo}
  end

  describe "tenant isolation" do
    test "summary refuses another tenant's flow", %{conn: conn} do
      other_flow = insert(:flow, tenant: insert(:tenant), name: "Other")

      assert %{"error" => _} =
               json_response(get(conn, "/api/v1/flows/#{other_flow.id}/analytics/summary"), 404)
    end

    test "nodes/funnel refuse another tenant's flow", %{conn: conn} do
      other_flow = insert(:flow, tenant: insert(:tenant))

      assert json_response(get(conn, "/api/v1/flows/#{other_flow.id}/analytics/nodes"), 404)
      assert json_response(get(conn, "/api/v1/flows/#{other_flow.id}/analytics/funnel"), 404)
    end

    test "summary returns data for the resolved tenant's own flow", %{conn: conn, demo: demo} do
      flow = insert(:flow, tenant: demo, name: "Mine")

      body = json_response(get(conn, "/api/v1/flows/#{flow.id}/analytics/summary"), 200)
      assert %{"entered" => _, "conversions" => _} = body["data"]
    end
  end

  describe "malformed params" do
    test "invalid ?from date does not 500", %{conn: conn, demo: demo} do
      flow = insert(:flow, tenant: demo)

      # Falls back to default range instead of raising
      assert json_response(
               get(conn, "/api/v1/flows/#{flow.id}/analytics/summary?from=garbage"),
               200
             )
    end
  end
end
