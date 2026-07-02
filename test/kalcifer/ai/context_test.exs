defmodule Kalcifer.AI.ContextTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.AI.Context

  import Kalcifer.Factory

  # ── Conversations ──────────────────────────────────────────

  describe "recent_api_messages/2" do
    test "returns only the most recent messages, in chronological order" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)
      base = ~U[2026-01-01 00:00:00Z]

      for i <- 1..5 do
        insert(:conversation_message,
          conversation: conv,
          role: "user",
          content: "m#{i}",
          inserted_at: DateTime.add(base, i, :second)
        )
      end

      msgs = Context.recent_api_messages(conv.id, 3)

      assert Enum.map(msgs, & &1.content) == ["m3", "m4", "m5"]
      assert Enum.all?(msgs, &(&1.role == "user"))
    end
  end

  describe "create_conversation/2" do
    test "creates a conversation for a tenant" do
      tenant = insert(:tenant)
      assert {:ok, conv} = Context.create_conversation(tenant.id)
      assert conv.tenant_id == tenant.id
      assert conv.status == "active"
    end

    test "creates with optional title" do
      tenant = insert(:tenant)
      assert {:ok, conv} = Context.create_conversation(tenant.id, %{title: "Test Chat"})
      assert conv.title == "Test Chat"
    end
  end

  describe "get_conversation_with_messages/1" do
    test "loads conversation with ordered messages" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)

      {:ok, _} = Context.add_message(conv.id, "user", "Hello")
      {:ok, _} = Context.add_message(conv.id, "assistant", "Hi there!")
      {:ok, _} = Context.add_message(conv.id, "user", "How are you?")

      loaded = Context.get_conversation_with_messages(conv.id)
      assert length(loaded.messages) == 3
      assert Enum.map(loaded.messages, & &1.role) == ["user", "assistant", "user"]
      assert Enum.map(loaded.messages, & &1.content) == ["Hello", "Hi there!", "How are you?"]
    end

    test "returns nil for nonexistent conversation" do
      assert Context.get_conversation_with_messages(Ecto.UUID.generate()) == nil
    end
  end

  describe "list_conversations/2" do
    test "lists active conversations for a tenant" do
      tenant = insert(:tenant)
      {:ok, c1} = Context.create_conversation(tenant.id, %{title: "First"})
      {:ok, c2} = Context.create_conversation(tenant.id, %{title: "Second"})

      convs = Context.list_conversations(tenant.id)
      ids = Enum.map(convs, & &1.id)
      assert c1.id in ids
      assert c2.id in ids
    end

    test "does not list archived conversations by default" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)
      {:ok, _archived} = Context.archive_conversation(conv)

      convs = Context.list_conversations(tenant.id)
      assert Enum.empty?(convs)
    end

    test "lists archived conversations when requested" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)
      {:ok, _archived} = Context.archive_conversation(conv)

      convs = Context.list_conversations(tenant.id, status: "archived")
      assert length(convs) == 1
    end
  end

  describe "archive_conversation/1" do
    test "changes status to archived" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)
      {:ok, archived} = Context.archive_conversation(conv)
      assert archived.status == "archived"
    end
  end

  describe "classify_conversation/3" do
    test "classifies an untyped conversation" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)

      {:ok, classified} = Context.classify_conversation(conv, "campaign", "Welcome კამპანია")
      assert classified.kind == "campaign"
      assert classified.title == "Welcome კამპანია"
    end

    test "rejects re-classification" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)
      {:ok, classified} = Context.classify_conversation(conv, "campaign")

      assert {:error, changeset} = Context.classify_conversation(classified, "flow")
      assert errors_on(changeset).kind
    end

    test "rejects invalid kind" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)

      assert {:error, changeset} = Context.classify_conversation(conv, "invalid_kind")
      assert errors_on(changeset).kind
    end
  end

  describe "link_entity/3" do
    test "links a conversation to an entity" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)
      entity_id = Ecto.UUID.generate()

      {:ok, linked} = Context.link_entity(conv, "Journey", entity_id)
      assert linked.entity_type == "Journey"
      assert linked.entity_id == entity_id
    end
  end

  describe "rename_conversation/2" do
    test "renames a conversation" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id, %{title: "Old"})

      {:ok, renamed} = Context.rename_conversation(conv, "New Name")
      assert renamed.title == "New Name"
    end

    test "rejects empty title" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)

      assert {:error, changeset} = Context.rename_conversation(conv, "")
      assert errors_on(changeset).title
    end
  end

  describe "delete_conversation/1" do
    test "deletes a conversation and its messages" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)
      {:ok, _} = Context.add_message(conv.id, "user", "Hello")

      {:ok, _} = Context.delete_conversation(conv)
      assert Context.get_conversation(conv.id) == nil
    end
  end

  # ── Messages ───────────────────────────────────────────────

  describe "add_message/4" do
    test "adds a user message" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)
      {:ok, msg} = Context.add_message(conv.id, "user", "Hello!")
      assert msg.role == "user"
      assert msg.content == "Hello!"
      assert msg.conversation_id == conv.id
    end

    test "adds an assistant message with tool_calls" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)

      tool_calls = [%{"name" => "list_flows", "input" => %{}}]
      {:ok, msg} = Context.add_message(conv.id, "assistant", "Let me check...", tool_calls)

      assert msg.tool_calls == tool_calls
    end
  end

  describe "get_api_messages/2" do
    test "returns messages formatted for Claude API" do
      tenant = insert(:tenant)
      {:ok, conv} = Context.create_conversation(tenant.id)

      {:ok, _} = Context.add_message(conv.id, "user", "Hi")
      {:ok, _} = Context.add_message(conv.id, "assistant", "Hello!")

      api_msgs = Context.get_api_messages(conv.id)

      assert api_msgs == [
               %{role: "user", content: "Hi"},
               %{role: "assistant", content: "Hello!"}
             ]
    end
  end

  # ── Memory ─────────────────────────────────────────────────

  describe "remember/4" do
    test "creates a new memory" do
      tenant = insert(:tenant)
      assert {:ok, mem} = Context.remember(tenant.id, "name", "David", "preference")
      assert mem.key == "name"
      assert mem.value == "David"
      assert mem.category == "preference"
    end

    test "upserts on same key" do
      tenant = insert(:tenant)
      {:ok, _} = Context.remember(tenant.id, "color", "blue")
      {:ok, updated} = Context.remember(tenant.id, "color", "red")
      assert updated.value == "red"

      # Only one memory with this key
      memories = Context.recall_all(tenant.id)
      color_memories = Enum.filter(memories, &(&1.key == "color"))
      assert length(color_memories) == 1
    end
  end

  describe "recall/2" do
    test "finds existing memory" do
      tenant = insert(:tenant)
      {:ok, _} = Context.remember(tenant.id, "lang", "Georgian")

      mem = Context.recall(tenant.id, "lang")
      assert mem.value == "Georgian"
    end

    test "returns nil for nonexistent key" do
      tenant = insert(:tenant)
      assert Context.recall(tenant.id, "nonexistent") == nil
    end
  end

  describe "recall_all/2" do
    test "returns all memories for tenant" do
      tenant = insert(:tenant)
      {:ok, _} = Context.remember(tenant.id, "a", "1")
      {:ok, _} = Context.remember(tenant.id, "b", "2")
      {:ok, _} = Context.remember(tenant.id, "c", "3")

      memories = Context.recall_all(tenant.id)
      assert length(memories) >= 3
    end

    test "filters by category" do
      tenant = insert(:tenant)
      {:ok, _} = Context.remember(tenant.id, "pref1", "v1", "preference")
      {:ok, _} = Context.remember(tenant.id, "gen1", "v2", "general")

      prefs = Context.recall_all(tenant.id, category: "preference")
      assert Enum.all?(prefs, &(&1.category == "preference"))
    end
  end

  describe "forget/2" do
    test "deletes a memory" do
      tenant = insert(:tenant)
      {:ok, _} = Context.remember(tenant.id, "temp", "data")
      {:ok, _deleted} = Context.forget(tenant.id, "temp")
      assert Context.recall(tenant.id, "temp") == nil
    end

    test "returns ok for nonexistent key" do
      tenant = insert(:tenant)
      assert {:ok, nil} = Context.forget(tenant.id, "nope")
    end
  end
end
