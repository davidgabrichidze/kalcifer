defmodule Kalcifer.AI.Context do
  @moduledoc """
  Context module for AI conversations and operator memory.

  Provides CRUD for:
  - Conversations — persisted chat sessions with message history
  - Memory — persistent key-value knowledge per tenant
  """

  import Ecto.Query

  alias Kalcifer.AI.{Conversation, ConversationMessage, Memory}
  alias Kalcifer.Repo

  # ── Conversations ─────────────────────────────────────────────

  def create_conversation(tenant_id, attrs \\ %{}) do
    %Conversation{}
    |> Conversation.create_changeset(Map.put(attrs, :tenant_id, tenant_id))
    |> Repo.insert()
  end

  def get_conversation(id) do
    Repo.get(Conversation, id)
  end

  def get_conversation(tenant_id, id) do
    Repo.get_by(Conversation, id: id, tenant_id: tenant_id)
  end

  def get_conversation_with_messages(id) do
    Conversation
    |> Repo.get(id)
    |> Repo.preload(messages: from(m in ConversationMessage, order_by: m.inserted_at))
  end

  def get_conversation_with_messages(tenant_id, id) do
    case Repo.get_by(Conversation, id: id, tenant_id: tenant_id) do
      nil ->
        nil

      conv ->
        Repo.preload(conv, messages: from(m in ConversationMessage, order_by: m.inserted_at))
    end
  end

  def list_conversations(tenant_id, opts \\ []) do
    status = Keyword.get(opts, :status, "active")
    kind = Keyword.get(opts, :kind)

    Conversation
    |> where([c], c.tenant_id == ^tenant_id and c.status == ^status)
    |> then(fn q ->
      if kind, do: where(q, [c], c.kind == ^kind), else: q
    end)
    |> order_by([c], desc: c.updated_at)
    |> limit(^Keyword.get(opts, :limit, 50))
    |> Repo.all()
  end

  def rename_conversation(%Conversation{} = conv, title) do
    conv
    |> Conversation.rename_changeset(title)
    |> Repo.update()
  end

  def archive_conversation(%Conversation{} = conv) do
    conv
    |> Conversation.archive_changeset()
    |> Repo.update()
  end

  def delete_conversation(%Conversation{} = conv) do
    Repo.delete(conv)
  end

  @doc "Classify a session — sets kind (campaign/flow/analysis/debug) and optional title."
  def classify_conversation(%Conversation{} = conv, kind, title \\ nil) do
    conv
    |> Conversation.classify_changeset(kind, title)
    |> Repo.update()
  end

  @doc "Link a classified conversation to a concrete entity (Journey, Flow, etc.)."
  def link_entity(%Conversation{} = conv, entity_type, entity_id) do
    conv
    |> Conversation.link_entity_changeset(entity_type, entity_id)
    |> Repo.update()
  end

  # ── Messages ──────────────────────────────────────────────────

  def add_message(conversation_id, role, content, tool_calls \\ nil) do
    %ConversationMessage{}
    |> ConversationMessage.changeset(%{
      conversation_id: conversation_id,
      role: role,
      content: content,
      tool_calls: tool_calls
    })
    |> Repo.insert()
  end

  def get_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    ConversationMessage
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Get messages formatted for the Claude API."
  def get_api_messages(conversation_id, opts \\ []) do
    conversation_id
    |> get_messages(opts)
    |> Enum.map(fn msg ->
      %{role: msg.role, content: msg.content}
    end)
  end

  @doc """
  Most recent messages (chronological order) formatted for the Claude API,
  capped to the last `limit`. Used to bound the history re-sent each turn so
  a long conversation can't outgrow the model's context window.
  """
  def recent_api_messages(conversation_id, limit \\ 100) do
    ConversationMessage
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
    |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
  end

  # ── Memory ────────────────────────────────────────────────────

  def remember(tenant_id, key, value, category \\ "general") do
    %Memory{}
    |> Memory.changeset(%{
      tenant_id: tenant_id,
      key: key,
      value: value,
      category: category
    })
    |> Repo.insert(
      on_conflict: {:replace, [:value, :category, :updated_at]},
      conflict_target: [:tenant_id, :key]
    )
  end

  def recall(tenant_id, key) do
    Repo.get_by(Memory, tenant_id: tenant_id, key: key)
  end

  def recall_all(tenant_id, opts \\ []) do
    category = Keyword.get(opts, :category)

    Memory
    |> where([m], m.tenant_id == ^tenant_id)
    |> then(fn q ->
      if category, do: where(q, [m], m.category == ^category), else: q
    end)
    |> order_by([m], asc: m.key)
    |> Repo.all()
  end

  def forget(tenant_id, key) do
    case recall(tenant_id, key) do
      nil -> {:ok, nil}
      memory -> Repo.delete(memory)
    end
  end
end
