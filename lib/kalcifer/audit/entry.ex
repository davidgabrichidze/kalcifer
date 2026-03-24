defmodule Kalcifer.Audit.Entry do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_log" do
    field :tenant_id, :binary_id
    field :actor, :string
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :details, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:tenant_id, :actor, :action, :resource_type, :resource_id, :details])
    |> validate_required([:tenant_id, :actor, :action, :resource_type])
  end
end
