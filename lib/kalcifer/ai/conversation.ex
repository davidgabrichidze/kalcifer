defmodule Kalcifer.AI.Conversation do
  @moduledoc """
  Schema for persisted chat conversations.

  A conversation starts untyped (kind = nil) and crystallizes into a
  concrete session type during the chat — campaign, flow, analysis, or debug.
  Once classified, the kind cannot change.

  When classified, entity_type + entity_id link to the concrete object
  (e.g., a Journey or Flow) created during the session.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_kinds ~w(campaign flow analysis debug)

  schema "conversations" do
    field :title, :string
    field :status, :string, default: "active"
    field :kind, :string
    field :entity_type, :string
    field :entity_id, :binary_id
    field :metadata, :map, default: %{}

    belongs_to :tenant, Kalcifer.Tenants.Tenant
    has_many :messages, Kalcifer.AI.ConversationMessage

    timestamps(type: :utc_datetime)
  end

  def valid_kinds, do: @valid_kinds

  def create_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :tenant_id, :metadata, :kind])
    |> validate_required([:tenant_id])
    |> validate_inclusion(:status, ~w(active archived))
    |> maybe_validate_kind()
  end

  def classify_changeset(conversation, kind, title \\ nil) do
    # Can only classify once — if already classified, reject
    if conversation.kind do
      conversation
      |> change()
      |> add_error(:kind, "session already classified as #{conversation.kind}")
    else
      attrs = %{kind: kind}
      attrs = if title, do: Map.put(attrs, :title, title), else: attrs

      conversation
      |> cast(attrs, [:kind, :title])
      |> validate_required([:kind])
      |> validate_inclusion(:kind, @valid_kinds)
    end
  end

  def link_entity_changeset(conversation, entity_type, entity_id) do
    conversation
    |> cast(%{entity_type: entity_type, entity_id: entity_id}, [:entity_type, :entity_id])
    |> validate_required([:entity_type, :entity_id])
  end

  def rename_changeset(conversation, title) do
    conversation
    |> cast(%{title: title}, [:title])
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
  end

  def archive_changeset(conversation) do
    change(conversation, status: "archived")
  end

  defp maybe_validate_kind(changeset) do
    case get_change(changeset, :kind) do
      nil -> changeset
      _kind -> validate_inclusion(changeset, :kind, @valid_kinds)
    end
  end
end
