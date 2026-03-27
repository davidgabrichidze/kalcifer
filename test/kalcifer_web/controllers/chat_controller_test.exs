defmodule KalciferWeb.ChatControllerTest do
  use KalciferWeb.ConnCase, async: true

  alias Kalcifer.AI.Context
  alias Kalcifer.Tenants

  import Kalcifer.Factory

  # ── Helpers ─────────────────────────────────────────────────

  # Get the demo tenant (auto-created by TenantResolver)
  defp ensure_demo_tenant do
    case Kalcifer.Repo.get_by(Kalcifer.Tenants.Tenant, name: "Demo Tenant") do
      %{} = t -> t
      nil ->
        {:ok, t} = Tenants.create_tenant(%{
          name: "Demo Tenant",
          api_key_hash: Tenants.hash_api_key("demo-dev-key")
        })
        t
    end
  end

  # ── A. Request Validation ─────────────────────────────────────

  describe "A. request validation" do
    test "A1: returns 400 when messages param is missing", %{conn: conn} do
      conn = post(conn, "/api/v1/chat", %{})
      assert json_response(conn, 400) == %{"error" => "messages parameter required"}
    end

    test "A2: accepts empty messages array as valid request", %{conn: conn} do
      conn = post(conn, "/api/v1/chat", %{"messages" => []})
      assert conn.status == 200
      assert {"content-type", ct} = List.keyfind(conn.resp_headers, "content-type", 0)
      assert String.contains?(ct, "text/event-stream")
    end
  end

  # ── B. Conversation Resolution ────────────────────────────────

  describe "B. conversation resolution" do
    test "B1: creates new conversation when none provided", %{conn: conn} do
      _conn = post(conn, "/api/v1/chat", %{
        "messages" => [%{"role" => "user", "content" => "hello B1"}]
      })

      tenant = ensure_demo_tenant()
      convs = Context.list_conversations(tenant.id)
      assert Enum.any?(convs, fn c ->
        msgs = Context.get_messages(c.id)
        Enum.any?(msgs, &(&1.content == "hello B1"))
      end)
    end

    test "B2: reuses existing conversation when valid id provided", %{conn: conn} do
      tenant = ensure_demo_tenant()
      {:ok, conv} = Context.create_conversation(tenant.id, %{title: "Existing"})

      _conn = post(conn, "/api/v1/chat", %{
        "messages" => [%{"role" => "user", "content" => "hello B2"}],
        "conversation_id" => conv.id
      })

      # Message should be in the SAME conversation
      messages = Context.get_messages(conv.id)
      assert Enum.any?(messages, &(&1.content == "hello B2"))
    end

    test "B3: creates new conversation for nonexistent id", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      _conn = post(conn, "/api/v1/chat", %{
        "messages" => [%{"role" => "user", "content" => "hello B3"}],
        "conversation_id" => fake_id
      })

      # Message should NOT be in fake conversation (it doesn't exist)
      assert Context.get_messages(fake_id) == []

      # But should exist in SOME conversation
      tenant = ensure_demo_tenant()
      convs = Context.list_conversations(tenant.id)
      assert Enum.any?(convs, fn c ->
        msgs = Context.get_messages(c.id)
        Enum.any?(msgs, &(&1.content == "hello B3"))
      end)
    end

    test "B4: rejects other tenant's conversation (security)", %{conn: conn} do
      other_tenant = insert(:tenant)
      {:ok, other_conv} = Context.create_conversation(other_tenant.id, %{title: "Secret"})
      {:ok, _} = Context.add_message(other_conv.id, "user", "private data")

      _conn = post(conn, "/api/v1/chat", %{
        "messages" => [%{"role" => "user", "content" => "hello B4"}],
        "conversation_id" => other_conv.id
      })

      # B4 message should NOT be in other tenant's conversation
      other_msgs = Context.get_messages(other_conv.id)
      refute Enum.any?(other_msgs, &(&1.content == "hello B4"))

      # Should be in a NEW conversation under demo tenant
      tenant = ensure_demo_tenant()
      convs = Context.list_conversations(tenant.id)
      assert Enum.any?(convs, fn c ->
        msgs = Context.get_messages(c.id)
        Enum.any?(msgs, &(&1.content == "hello B4"))
      end)
    end

    test "B5: loads message history from existing conversation", %{conn: conn} do
      tenant = ensure_demo_tenant()
      {:ok, conv} = Context.create_conversation(tenant.id)
      {:ok, _} = Context.add_message(conv.id, "user", "old question")
      {:ok, _} = Context.add_message(conv.id, "assistant", "old answer")

      _conn = post(conn, "/api/v1/chat", %{
        "messages" => [%{"role" => "user", "content" => "new question"}],
        "conversation_id" => conv.id
      })

      messages = Context.get_messages(conv.id)
      contents = Enum.map(messages, & &1.content)
      assert "old question" in contents
      assert "old answer" in contents
      assert "new question" in contents
    end
  end

  # ── C. User Message Persistence ───────────────────────────────

  describe "C. user message persistence" do
    test "C1: single user message saved to DB", %{conn: conn} do
      tenant = ensure_demo_tenant()
      {:ok, conv} = Context.create_conversation(tenant.id)

      _conn = post(conn, "/api/v1/chat", %{
        "messages" => [%{"role" => "user", "content" => "C1 test message"}],
        "conversation_id" => conv.id
      })

      messages = Context.get_messages(conv.id)
      user_msgs = Enum.filter(messages, &(&1.role == "user"))
      assert Enum.any?(user_msgs, &(&1.content == "C1 test message"))
    end

    test "C2: multiple user messages in one request all saved", %{conn: conn} do
      tenant = ensure_demo_tenant()
      {:ok, conv} = Context.create_conversation(tenant.id)

      _conn = post(conn, "/api/v1/chat", %{
        "messages" => [
          %{"role" => "user", "content" => "first C2"},
          %{"role" => "user", "content" => "second C2"}
        ],
        "conversation_id" => conv.id
      })

      messages = Context.get_messages(conv.id)
      user_contents = messages |> Enum.filter(&(&1.role == "user")) |> Enum.map(& &1.content)
      assert "first C2" in user_contents
      assert "second C2" in user_contents
    end

    test "C3: only user role messages are saved (assistant filtered out)", %{conn: conn} do
      tenant = ensure_demo_tenant()
      {:ok, conv} = Context.create_conversation(tenant.id)

      _conn = post(conn, "/api/v1/chat", %{
        "messages" => [
          %{"role" => "assistant", "content" => "should not save"},
          %{"role" => "user", "content" => "C3 real message"}
        ],
        "conversation_id" => conv.id
      })

      messages = Context.get_messages(conv.id)
      contents = Enum.map(messages, & &1.content)
      # User message saved
      assert "C3 real message" in contents
      # Assistant message NOT saved by ChatController (only user messages are saved on input)
      refute "should not save" in contents
    end
  end
end
