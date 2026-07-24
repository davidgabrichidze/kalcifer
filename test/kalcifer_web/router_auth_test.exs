defmodule KalciferWeb.RouterAuthTest do
  @moduledoc """
  End-to-end guard on the routes the operator frontend shares with API-key
  callers. These used to run with no credential at all and resolve to an
  auto-created "Demo Tenant" in every environment.
  """

  # async: false — toggles the global :allow_tenant_header flag.
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Tenants
  alias KalciferWeb.AuthController

  setup do
    previous = Application.get_env(:kalcifer, :allow_tenant_header, false)
    on_exit(fn -> Application.put_env(:kalcifer, :allow_tenant_header, previous) end)
    :ok
  end

  # Every route that previously served an anonymous caller. Read routes leak
  # another tenant's data; write routes mutate it.
  @guarded [
    {:get, "/api/v1/settings"},
    {:get, "/api/v1/settings/stats"},
    {:get, "/api/v1/audit"},
    {:get, "/api/v1/deliveries"},
    {:get, "/api/v1/deliveries/stats"},
    {:get, "/api/v1/flows"},
    {:get, "/api/v1/journeys"},
    {:get, "/api/v1/conversations"}
  ]

  describe "in production (allow_tenant_header off)" do
    setup do
      Application.put_env(:kalcifer, :allow_tenant_header, false)
      :ok
    end

    for {method, path} <- @guarded do
      test "#{String.upcase(to_string(method))} #{path} rejects an anonymous caller", %{
        conn: conn
      } do
        conn = unquote(method)(conn, unquote(path))
        assert json_response(conn, 401)
      end
    end

    test "POST /api/v1/settings/regenerate-api-key rejects an anonymous caller", %{conn: conn} do
      conn = post(conn, "/api/v1/settings/regenerate-api-key")
      assert json_response(conn, 401)
    end

    test "POST /api/v1/flows/import rejects an anonymous caller", %{conn: conn} do
      conn = post(conn, "/api/v1/flows/import", %{})
      assert json_response(conn, 401)
    end

    test "PUT on a flow version rejects an anonymous caller", %{conn: conn} do
      flow = insert(:flow)
      conn = put(conn, "/api/v1/flows/#{flow.id}/versions/1", %{})
      assert json_response(conn, 401)
    end

    test "POST /api/v1/chat rejects an anonymous caller", %{conn: conn} do
      conn = post(conn, "/api/v1/chat", %{"message" => "hello"})
      assert json_response(conn, 401)
    end

    test "an API key gets through", %{conn: conn} do
      raw = "router-test-key"
      insert(:tenant, api_key_hash: Tenants.hash_api_key(raw))

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw}")
        |> get("/api/v1/flows")

      assert json_response(conn, 200)
    end

    test "a Google session token gets through", %{conn: conn} do
      user = insert(:user)
      token = AuthController.generate_session_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/flows")

      assert json_response(conn, 200)
    end

    test "a session token scopes reads to that user's tenant", %{conn: conn} do
      user = insert(:user)
      insert(:flow, tenant: user.tenant, name: "Mine")
      insert(:flow, name: "Someone else's")

      token = AuthController.generate_session_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/flows")

      names = json_response(conn, 200)["data"] |> Enum.map(& &1["name"])

      assert "Mine" in names
      refute "Someone else's" in names
    end
  end

  describe "public routes stay public" do
    setup do
      Application.put_env(:kalcifer, :allow_tenant_header, false)
      :ok
    end

    test "health needs no credential", %{conn: conn} do
      assert json_response(get(conn, "/api/v1/health"), 200)
    end
  end

  describe "GET /api/v1/auth/me" do
    test "returns the user for a valid session token", %{conn: conn} do
      user = insert(:user)
      token = AuthController.generate_session_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/auth/me")

      body = json_response(conn, 200)

      assert body["user"]["id"] == user.id
      assert body["user"]["email"] == user.email
      assert body["user"]["tenant_id"] == user.tenant_id
    end

    test "401s without a token", %{conn: conn} do
      assert json_response(get(conn, "/api/v1/auth/me"), 401)
    end
  end

  describe "in dev (allow_tenant_header on)" do
    setup do
      Application.put_env(:kalcifer, :allow_tenant_header, true)
      :ok
    end

    test "the frontend still works before anyone logs in", %{conn: conn} do
      assert json_response(get(conn, "/api/v1/flows"), 200)
    end
  end
end
