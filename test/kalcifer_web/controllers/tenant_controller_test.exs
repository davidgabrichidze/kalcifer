defmodule KalciferWeb.TenantControllerTest do
  use KalciferWeb.ConnCase, async: true

  import Kalcifer.Factory

  describe "GET /api/v1/tenants" do
    test "lists tenants with the resolved tenant marked active", %{conn: conn} do
      tenant_a = insert(:tenant, name: "Acme")
      insert(:tenant, name: "Beta Corp")

      conn =
        conn
        |> put_req_header("x-tenant-id", tenant_a.id)
        |> get("/api/v1/tenants")

      body = json_response(conn, 200)
      names = Enum.map(body["data"], & &1["name"])

      assert "Acme" in names
      assert "Beta Corp" in names

      active = Enum.find(body["data"], & &1["active"])
      assert active["id"] == tenant_a.id
    end

    test "falls back to demo tenant without headers", %{conn: conn} do
      conn = get(conn, "/api/v1/tenants")
      body = json_response(conn, 200)

      active = Enum.find(body["data"], & &1["active"])
      assert active["name"] == "Demo Tenant"
    end

    test "ignores invalid x-tenant-id values", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-tenant-id", "not-a-uuid")
        |> get("/api/v1/tenants")

      body = json_response(conn, 200)
      active = Enum.find(body["data"], & &1["active"])
      assert active["name"] == "Demo Tenant"
    end
  end
end
