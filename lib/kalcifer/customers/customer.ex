defmodule Kalcifer.Customers.Customer do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Tenants.Tenant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "customers" do
    field :external_id, :string
    field :email, :string
    field :phone, :string
    field :name, :string
    field :properties, :map, default: %{}
    field :tags, {:array, :string}, default: []
    field :preferences, :map, default: %{}
    field :last_seen_at, :utc_datetime

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime)
  end

  def create_changeset(customer, attrs) do
    customer
    |> cast(attrs, [
      :external_id,
      :email,
      :phone,
      :name,
      :properties,
      :tags,
      :preferences,
      :tenant_id
    ])
    |> validate_required([:external_id, :tenant_id])
    |> unique_constraint(:external_id, name: :customers_tenant_id_external_id_index)
    |> foreign_key_constraint(:tenant_id)
  end

  def update_changeset(customer, attrs) do
    customer
    |> cast(attrs, [:email, :phone, :name, :properties, :preferences, :last_seen_at])
  end
end
