defmodule Kalcifer.Tenants.Tenant do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tenants" do
    field :name, :string
    field :api_key_hash, :string
    field :settings, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :api_key_hash, :settings])
    |> validate_required([:name, :api_key_hash])
    |> unique_constraint(:name)
    |> unique_constraint(:api_key_hash)
  end
end
