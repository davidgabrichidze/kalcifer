defmodule Kalcifer.Customers.Segment do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Tenants.Tenant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(static dynamic)

  schema "segments" do
    field :name, :string
    field :description, :string
    field :type, :string, default: "dynamic"
    field :rules, {:array, :map}, default: []

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(segment, attrs) do
    segment
    |> cast(attrs, [:name, :description, :type, :rules, :tenant_id])
    |> validate_required([:name, :tenant_id])
    |> validate_inclusion(:type, @types)
    |> foreign_key_constraint(:tenant_id)
  end
end
