defmodule Kalcifer.AI.Conversation do
  @moduledoc """
  Schema for persisted chat conversations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversations" do
    field :title, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :tenant, Kalcifer.Tenants.Tenant
    has_many :messages, Kalcifer.AI.ConversationMessage

    timestamps(type: :utc_datetime)
  end

  def create_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :tenant_id, :metadata])
    |> validate_required([:tenant_id])
    |> validate_inclusion(:status, ~w(active archived))
  end

  def archive_changeset(conversation) do
    change(conversation, status: "archived")
  end
end
