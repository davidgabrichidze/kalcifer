defmodule KalciferWeb.ChatControllerTest do
  use KalciferWeb.ConnCase, async: true

  alias Kalcifer.AI.Context

  import Kalcifer.Factory

  describe "POST /api/v1/chat" do
    test "returns 400 when messages param is missing", %{conn: conn} do
      conn = post(conn, "/api/v1/chat", %{})
      assert json_response(conn, 400) == %{"error" => "messages parameter required"}
    end

    test "returns 200 with SSE content type for valid request", %{conn: conn} do
      # This will fail to reach Claude API (no key), but should still
      # set up the connection correctly and return init event
      conn = post(conn, "/api/v1/chat", %{
        "messages" => [%{"role" => "user", "content" => "hello"}]
      })

      assert conn.status == 200
      assert {"content-type", content_type} =
        List.keyfind(conn.resp_headers, "content-type", 0)
      assert String.contains?(content_type, "text/event-stream")
    end

    test "creates a conversation when none provided", %{conn: conn} do
      _conn = post(conn, "/api/v1/chat", %{
        "messages" => [%{"role" => "user", "content" => "hello"}]
      })

      # Find the demo tenant's conversations
      tenant = Kalcifer.Repo.get_by(Kalcifer.Tenants.Tenant, name: "Demo Tenant")
      assert tenant != nil

      convs = Context.list_conversations(tenant.id)
      assert length(convs) >= 1
    end

    test "saves user message to conversation", %{conn: conn} do
      _conn = post(conn, "/api/v1/chat", %{
        "messages" => [%{"role" => "user", "content" => "test message"}]
      })

      tenant = Kalcifer.Repo.get_by(Kalcifer.Tenants.Tenant, name: "Demo Tenant")
      convs = Context.list_conversations(tenant.id)
      conv = List.first(convs)

      messages = Context.get_messages(conv.id)
      user_msgs = Enum.filter(messages, &(&1.role == "user"))
      assert Enum.any?(user_msgs, &(&1.content == "test message"))
    end

    test "reuses existing conversation when conversation_id provided", %{conn: conn} do
      tenant = insert(:tenant, name: "Demo Tenant")
      {:ok, conv} = Context.create_conversation(tenant.id, %{title: "Existing"})
      {:ok, _} = Context.add_message(conv.id, "user", "old message")
      {:ok, _} = Context.add_message(conv.id, "assistant", "old response")

      _conn = post(conn, "/api/v1/chat", %{
        "messages" => [%{"role" => "user", "content" => "new question"}],
        "conversation_id" => conv.id
      })

      messages = Context.get_messages(conv.id)
      assert length(messages) >= 3
      assert Enum.any?(messages, &(&1.content == "new question"))
    end
  end
end
