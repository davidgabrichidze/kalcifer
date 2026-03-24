defmodule KalciferWeb.Plugs.ApiKeyAuthTest do
  use KalciferWeb.ConnCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Tenants

  @raw_api_key "test_api_key_for_auth_plug"

  setup do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)
    {:ok, tenant: tenant}
  end

  # Use an authenticated-only route (POST /events is only in the :authenticated pipeline)
  @auth_route "/api/v1/events"

  test "authenticates valid API key and sets current_tenant", %{conn: conn, tenant: tenant} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")
      |> post(@auth_route, %{})

    assert conn.assigns.current_tenant.id == tenant.id
  end

  test "rejects missing authorization header", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(@auth_route, %{})

    assert json_response(conn, 401) == %{"error" => "invalid_api_key"}
  end

  test "rejects invalid API key", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer wrong_key")
      |> put_req_header("content-type", "application/json")
      |> post(@auth_route, %{})

    assert json_response(conn, 401) == %{"error" => "invalid_api_key"}
  end

  test "rejects malformed authorization header", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Token something")
      |> put_req_header("content-type", "application/json")
      |> post(@auth_route, %{})

    assert json_response(conn, 401) == %{"error" => "invalid_api_key"}
  end

  test "rejects empty bearer token", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer ")
      |> put_req_header("content-type", "application/json")
      |> post(@auth_route, %{})

    assert json_response(conn, 401) == %{"error" => "invalid_api_key"}
  end

  test "rejects lowercase bearer prefix", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")
      |> post(@auth_route, %{})

    assert json_response(conn, 401) == %{"error" => "invalid_api_key"}
  end
end
