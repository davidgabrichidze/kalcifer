defmodule Kalcifer.AI.Context do
  @moduledoc """
  Context module for AI conversations and operator memory.

  Provides CRUD for:
  - Conversations — persisted chat sessions with message history
  - Memory — persistent key-value knowledge per tenant
  """

  import Ecto.Query

  alias Kalcifer.Repo
  alias Kalcifer.AI.{Conversation, ConversationMessage, Memory}

  # ── Conversations ─────────────────────────────────────────────

  def create_conversation(tenant_id, attrs \\ %{}) do
    %Conversation{}
    |> Conversation.create_changeset(Map.put(attrs, :tenant_id, tenant_id))
    |> Repo.insert()
  end

  def get_conversation(id) do
    Repo.get(Conversation, id)
  end

  def get_conversation_with_messages(id) do
    Conversation
    |> Repo.get(id)
    |> Repo.preload(messages: from(m in ConversationMessage, order_by: m.inserted_at))
  end

  def list_conversations(tenant_id, opts \\ []) do
    status = Keyword.get(opts, :status, "active")

    Conversation
    |> where([c], c.tenant_id == ^tenant_id and c.status == ^status)
    |> order_by([c], desc: c.updated_at)
    |> limit(^Keyword.get(opts, :limit, 50))
    |> Repo.all()
  end

  def archive_conversation(%Conversation{} = conv) do
    conv
    |> Conversation.archive_changeset()
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
