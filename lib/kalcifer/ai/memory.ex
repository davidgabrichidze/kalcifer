defmodule Kalcifer.AI.Memory do
  @moduledoc """
  Operator memory — persistent key-value knowledge per tenant.

  Kalcifer uses this to remember things across conversations:
  preferences, patterns, common requests, project context.

  Categories: "general", "preference", "pattern", "context"
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "operator_memories" do
    field :key, :string
    field :value, :string
    field :category, :string, default: "general"

    belongs_to :tenant, Kalcifer.Tenants.Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:key, :value, :category, :tenant_id])
    |> validate_required([:key, :value, :tenant_id])
    |> validate_inclusion(:category, ~w(general preference pattern context))
    |> unique_constraint([:tenant_id, :key])
  end
end
