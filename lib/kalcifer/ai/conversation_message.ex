defmodule Kalcifer.AI.ConversationMessage do
  @moduledoc """
  Schema for individual messages within a conversation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversation_messages" do
    field :role, :string
    field :content, :string
    field :tool_calls, {:array, :map}

    belongs_to :conversation, Kalcifer.AI.Conversation

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :tool_calls, :conversation_id])
    |> validate_required([:role, :content, :conversation_id])
    |> validate_inclusion(:role, ~w(user assistant))
  end
end
