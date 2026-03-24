defmodule Kalcifer.Accounts.User do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Tenants.Tenant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar_url, :string
    field :google_uid, :string

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar_url, :google_uid, :tenant_id])
    |> validate_required([:email, :tenant_id])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
    |> unique_constraint(:google_uid)
    |> foreign_key_constraint(:tenant_id)
  end
end
