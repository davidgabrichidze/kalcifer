defmodule KalciferWeb.ChatControllerTest do
  use KalciferWeb.ConnCase, async: true

  alias Kalcifer.AI.Context

  import Kalcifer.Factory

  # ── A. Request Validation ─────────────────────────────────────

  describe "A. request validation" do
    test "A1: returns 400 when messages param is missing", %{conn: conn} do
      conn = post(conn, "/api/v1/chat", %{})
      assert json_response(conn, 400) == %{"error" => "messages parameter required"}
    end

    test "A2: accepts empty messages array as valid request", %{conn: conn} do
      conn =
        post(conn, "/api/v1/chat", %{
          "messages" => []
        })

      # Should still set up SSE connection (200) and emit init event
      assert conn.status == 200

      assert {"content-type", content_type} =
               List.keyfind(conn.resp_headers, "content-type", 0)

      assert String.contains?(content_type, "text/event-stream")
    end
  end
end
