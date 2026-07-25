defmodule KalciferWeb.Plugs.ResolveTenantTest do
  # async: false — toggles the global :allow_tenant_header flag.
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Tenants
  alias KalciferWeb.AuthController
  alias KalciferWeb.Plugs.ResolveTenant
  alias KalciferWeb.Plugs.UserAuth

  setup do
    previous = Application.get_env(:kalcifer, :allow_tenant_header, false)
    on_exit(fn -> Application.put_env(:kalcifer, :allow_tenant_header, previous) end)
    :ok
  end

  describe "in production (allow_tenant_header off)" do
    setup do
      Application.put_env(:kalcifer, :allow_tenant_header, false)
      :ok
    end

    test "halts with 401 when the request carries no credential", %{conn: conn} do
      conn = ResolveTenant.call(conn, [])

      assert conn.halted
      assert conn.status == 401
      assert %{"code" => "unauthorized"} = Jason.decode!(conn.resp_body)
    end

    test "halts with 401 for a bogus Bearer token", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer nonsense")
        |> ResolveTenant.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "assigns the tenant for a valid API key", %{conn: conn} do
      raw = "plug-test-key"
      tenant = insert(:tenant, api_key_hash: Tenants.hash_api_key(raw))

      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer #{raw}")
        |> ResolveTenant.call([])

      refute conn.halted
      assert conn.assigns.current_tenant.id == tenant.id
    end

    test "assigns the tenant for a Google session token", %{conn: conn} do
      user = insert(:user)
      token = AuthController.generate_session_token(user)

      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> UserAuth.call([])
        |> ResolveTenant.call([])

      refute conn.halted
      assert conn.assigns.current_user.id == user.id
      assert conn.assigns.current_tenant.id == user.tenant_id
    end

    test "an expired session token does not resolve", %{conn: conn} do
      user = insert(:user)
      old_ts = to_string(System.system_time(:second) - 31 * 24 * 3600)
      payload = "#{user.id}.#{old_ts}"

      sig =
        :crypto.mac(:hmac, :sha256, "test-session-secret", payload)
        |> Base.url_encode64(padding: false)

      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer #{payload}.#{sig}")
        |> UserAuth.call([])
        |> ResolveTenant.call([])

      assert conn.halted
      assert conn.status == 401
    end
  end

  describe "in dev (allow_tenant_header on)" do
    setup do
      Application.put_env(:kalcifer, :allow_tenant_header, true)
      :ok
    end

    test "an anonymous request still works, on the demo tenant", %{conn: conn} do
      conn = ResolveTenant.call(conn, [])

      refute conn.halted
      assert conn.assigns.current_tenant.name == "Demo Tenant"
    end

    test "the x-tenant-id header selects the tenant", %{conn: conn} do
      tenant = insert(:tenant)

      conn =
        conn
        |> Plug.Conn.put_req_header("x-tenant-id", tenant.id)
        |> ResolveTenant.call([])

      refute conn.halted
      assert conn.assigns.current_tenant.id == tenant.id
    end
  end
end
