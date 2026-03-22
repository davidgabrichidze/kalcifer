defmodule KalciferWeb.ChatControllerTest do
  use KalciferWeb.ConnCase, async: true

  describe "POST /api/v1/chat" do
    test "returns 400 when messages param is missing", %{conn: conn} do
      conn = post(conn, "/api/v1/chat", %{})
      assert json_response(conn, 400) == %{"error" => "messages parameter required"}
    end
  end
end
