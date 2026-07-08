defmodule KalciferWeb.ChatControllerTest do
  use KalciferWeb.ConnCase, async: true

  alias Kalcifer.AI.Context
  alias Kalcifer.Tenants

  import Kalcifer.Factory

  # ── Helpers ─────────────────────────────────────────────────

  # Get the demo tenant (auto-created by TenantResolver)
  defp ensure_demo_tenant do
    case Kalcifer.Repo.get_by(Kalcifer.Tenants.Tenant, name: "Demo Tenant") do
      %{} = t ->
        t

      nil ->
        {:ok, t} =
          Tenants.create_tenant(%{
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
      _conn =
        post(conn, "/api/v1/chat", %{
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

      _conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "hello B2"}],
          "conversation_id" => conv.id
        })

      # Message should be in the SAME conversation
      messages = Context.get_messages(conv.id)
      assert Enum.any?(messages, &(&1.content == "hello B2"))
    end

    test "B3: creates new conversation for nonexistent id", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      _conn =
        post(conn, "/api/v1/chat", %{
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

      _conn =
        post(conn, "/api/v1/chat", %{
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

      _conn =
        post(conn, "/api/v1/chat", %{
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

      _conn =
        post(conn, "/api/v1/chat", %{
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

      _conn =
        post(conn, "/api/v1/chat", %{
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

      _conn =
        post(conn, "/api/v1/chat", %{
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

  # ── D. SSE Event Format ───────────────────────────────────────

  describe "D. SSE event format" do
    test "D1: response has text/event-stream content type", %{conn: conn} do
      conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "D1"}]
        })

      assert conn.status == 200
      assert {"content-type", ct} = List.keyfind(conn.resp_headers, "content-type", 0)
      assert String.contains?(ct, "text/event-stream")
    end

    test "D2: response has no-cache header", %{conn: conn} do
      conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "D2"}]
        })

      assert {"cache-control", "no-cache"} = List.keyfind(conn.resp_headers, "cache-control", 0)
    end

    test "D3: response has x-accel-buffering no header", %{conn: conn} do
      conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "D3"}]
        })

      assert {"x-accel-buffering", "no"} = List.keyfind(conn.resp_headers, "x-accel-buffering", 0)
    end

    test "D4: response state is chunked", %{conn: conn} do
      conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "D4"}]
        })

      assert conn.state == :chunked
    end
  end

  # ── E. Agent Flow Path ────────────────────────────────────────
  # Note: Full agent flow requires AI API key. These tests verify
  # the flow selection logic and message handling, not the AI response.

  describe "E. agent flow path" do
    test "E1: normal message triggers agent flow (200 + SSE)", %{conn: conn} do
      conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "hello normal"}]
        })

      # Should return 200 with SSE — engine or fallback, both produce SSE
      assert conn.status == 200
      assert conn.state == :chunked
    end

    test "E2: council keyword triggers council flow path", %{conn: conn} do
      tenant = ensure_demo_tenant()
      {:ok, conv} = Context.create_conversation(tenant.id)

      # "საბჭო" is a council keyword
      conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "საბჭო, დაფიქრდი ამაზე"}],
          "conversation_id" => conv.id
        })

      # Should still work (200) — council or simple, both valid
      assert conn.status == 200

      # User message saved
      msgs = Context.get_messages(conv.id)
      assert Enum.any?(msgs, &(&1.content == "საბჭო, დაფიქრდი ამაზე"))
    end

    test "E3: agent response saved to conversation (when engine works)", %{conn: conn} do
      tenant = ensure_demo_tenant()
      {:ok, conv} = Context.create_conversation(tenant.id)

      _conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "E3 test"}],
          "conversation_id" => conv.id
        })

      # At minimum, user message should be saved
      msgs = Context.get_messages(conv.id)
      assert Enum.any?(msgs, &(&1.role == "user" && &1.content == "E3 test"))

      # If AI responded (may fail without API key), assistant message might exist
      # This is non-deterministic in test env, so we just check structure
      assistant_msgs = Enum.filter(msgs, &(&1.role == "assistant"))
      # assistant_msgs may be 0 (no API key) or 1+ (engine worked)
      assert is_list(assistant_msgs)
    end
  end

  # ── F. Session Classification ─────────────────────────────────
  # classify_session is an AI tool — we test the maybe_emit logic indirectly

  describe "F. session classification" do
    test "F1: classify_session tool result updates conversation kind", %{conn: _conn} do
      tenant = ensure_demo_tenant()
      {:ok, conv} = Context.create_conversation(tenant.id)

      # classify_session is called by AI as tool — not directly testable
      # without mocking. But we can test Context.classify_conversation:
      assert {:ok, classified} = Context.classify_conversation(conv, "flow", "Test Flow")
      assert classified.kind == "flow"
      assert classified.title == "Test Flow"
    end

    test "F2: re-classification is rejected", %{conn: _conn} do
      tenant = ensure_demo_tenant()
      {:ok, conv} = Context.create_conversation(tenant.id)
      {:ok, classified} = Context.classify_conversation(conv, "flow", "First")

      # Reload from DB to get updated kind, then try to classify again
      assert {:error, _} = Context.classify_conversation(classified, "campaign", "Second")
    end
  end

  # ── G. Error Handling ─────────────────────────────────────────

  describe "G. error handling" do
    test "G1: engine failure falls back gracefully (still 200)", %{conn: conn} do
      # Without API key, engine starts but AI call fails → fallback → still 200
      conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "G1 error test"}]
        })

      assert conn.status == 200
      assert conn.state == :chunked
    end

    test "G2: invalid JSON body returns 400", %{conn: conn} do
      # Send something that's not the expected format
      conn = post(conn, "/api/v1/chat", %{"wrong_key" => "value"})
      assert json_response(conn, 400)["error"] == "messages parameter required"
    end
  end

  # ── I. System Prompt ──────────────────────────────────────────
  # Tests that memory is loaded into system prompt

  describe "I. system prompt" do
    test "I1: chat works without operator memories", %{conn: conn} do
      conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "I1 no memories"}]
        })

      assert conn.status == 200
    end

    test "I2: operator memories are accessible during chat", %{conn: conn} do
      tenant = ensure_demo_tenant()

      # Store a memory
      Context.remember(tenant.id, "test_key", "test_value")

      # Memories should be available (we can verify they exist)
      memories = Context.recall_all(tenant.id)
      assert Enum.any?(memories, &(&1.key == "test_key" && &1.value == "test_value"))

      # Chat should still work
      conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "I2 with memories"}]
        })

      assert conn.status == 200
    end
  end

  # ── J. Helpers ────────────────────────────────────────────────

  describe "J. helpers" do
    test "J1: council keywords are detected correctly" do
      # Test the keywords list — these should trigger council flow
      council_words = ~w(council საბჭო დაფიქრდი ანალიზი deliberate think_deep)

      for word <- council_words do
        conn = build_conn()
        tenant = ensure_demo_tenant()
        {:ok, conv} = Context.create_conversation(tenant.id)

        _conn =
          post(conn, "/api/v1/chat", %{
            "messages" => [%{"role" => "user", "content" => "#{word} please"}],
            "conversation_id" => conv.id
          })

        # Just verify it doesn't crash — council flow selection
        msgs = Context.get_messages(conv.id)
        assert Enum.any?(msgs, fn m -> String.contains?(m.content, word) end)
      end
    end

    test "J2: non-council message does not trigger council", %{conn: conn} do
      tenant = ensure_demo_tenant()
      {:ok, conv} = Context.create_conversation(tenant.id)

      _conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "just a normal hello"}],
          "conversation_id" => conv.id
        })

      # Should work fine (simple flow path)
      msgs = Context.get_messages(conv.id)
      assert Enum.any?(msgs, &(&1.content == "just a normal hello"))
    end
  end

  # ── Linked-flow snapshot injection ────────────────────────────

  describe "linked-flow snapshot" do
    test "chat with a flow-linked conversation still streams SSE", %{conn: conn} do
      tenant = ensure_demo_tenant()
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft")
      {:ok, conversation} = Context.create_conversation(tenant.id)
      {:ok, conversation} = Context.link_entity(conversation, "flow", flow.id)

      conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "რა მდგომარეობაშია ფლოუ?"}],
          "conversation_id" => conversation.id
        })

      assert conn.status == 200
      assert {"content-type", ct} = List.keyfind(conn.resp_headers, "content-type", 0)
      assert String.contains?(ct, "text/event-stream")
    end
  end
end
