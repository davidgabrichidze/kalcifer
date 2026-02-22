defmodule KalciferWeb.HealthControllerTest do
  use KalciferWeb.ConnCase, async: true

  test "GET /api/v1/health returns ok", %{conn: conn} do
    conn = get(conn, "/api/v1/health")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
