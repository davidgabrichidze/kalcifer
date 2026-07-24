defmodule KalciferWeb.TenantResolverTest do
  # async: false — toggles the global :allow_tenant_header flag
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Tenants
  alias KalciferWeb.TenantResolver

  setup do
    previous = Application.get_env(:kalcifer, :allow_tenant_header, false)
    on_exit(fn -> Application.put_env(:kalcifer, :allow_tenant_header, previous) end)
    :ok
  end

  describe "x-tenant-id header" do
    test "is honored when allow_tenant_header is true", %{conn: conn} do
      Application.put_env(:kalcifer, :allow_tenant_header, true)
      tenant = insert(:tenant)

      resolved =
        conn
        |> Plug.Conn.put_req_header("x-tenant-id", tenant.id)
        |> TenantResolver.resolve()

      assert resolved.id == tenant.id
    end

    test "is ignored when allow_tenant_header is false (prod)", %{conn: conn} do
      Application.put_env(:kalcifer, :allow_tenant_header, false)
      tenant = insert(:tenant, name: "Victim")

      conn = Plug.Conn.put_req_header(conn, "x-tenant-id", tenant.id)

      # No demo-tenant consolation prize either — nothing resolves at all.
      assert TenantResolver.resolve_or_nil(conn) == nil
    end

    test "a valid Bearer token still resolves regardless of the flag", %{conn: conn} do
      Application.put_env(:kalcifer, :allow_tenant_header, false)
      raw = "resolver-test-key"
      tenant = insert(:tenant, api_key_hash: Tenants.hash_api_key(raw))

      resolved =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer #{raw}")
        |> TenantResolver.resolve()

      assert resolved.id == tenant.id
    end
  end

  describe "demo tenant fallback" do
    test "an anonymous request gets the demo tenant in dev", %{conn: conn} do
      Application.put_env(:kalcifer, :allow_tenant_header, true)

      resolved = TenantResolver.resolve(conn)

      assert resolved.name == "Demo Tenant"
    end

    test "an anonymous request resolves to nothing in prod", %{conn: conn} do
      Application.put_env(:kalcifer, :allow_tenant_header, false)

      assert TenantResolver.resolve_or_nil(conn) == nil
    end

    test "no demo tenant is created in prod", %{conn: conn} do
      Application.put_env(:kalcifer, :allow_tenant_header, false)

      TenantResolver.resolve_or_nil(conn)

      assert Kalcifer.Repo.get_by(Kalcifer.Tenants.Tenant, name: "Demo Tenant") == nil
    end

    test "an unknown Bearer token does not fall through to the demo tenant in prod", %{conn: conn} do
      Application.put_env(:kalcifer, :allow_tenant_header, false)

      conn = Plug.Conn.put_req_header(conn, "authorization", "Bearer not-a-real-key")

      assert TenantResolver.resolve_or_nil(conn) == nil
    end
  end

  describe "resolve/1 without a tenant" do
    test "raises rather than inventing one, so a misconfigured pipeline is loud", %{conn: conn} do
      Application.put_env(:kalcifer, :allow_tenant_header, false)

      assert_raise RuntimeError, ~r/must pipe through/, fn ->
        TenantResolver.resolve(conn)
      end
    end
  end

  describe "assigned tenant" do
    test "wins over every other source", %{conn: conn} do
      Application.put_env(:kalcifer, :allow_tenant_header, true)
      assigned = insert(:tenant, name: "Assigned")
      other = insert(:tenant, name: "Header")

      resolved =
        conn
        |> Plug.Conn.assign(:current_tenant, assigned)
        |> Plug.Conn.put_req_header("x-tenant-id", other.id)
        |> TenantResolver.resolve()

      assert resolved.id == assigned.id
    end
  end
end
