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

      resolved =
        conn
        |> Plug.Conn.put_req_header("x-tenant-id", tenant.id)
        |> TenantResolver.resolve()

      # Falls back to demo tenant instead of the requested one
      refute resolved.id == tenant.id
      assert resolved.name == "Demo Tenant"
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
end
