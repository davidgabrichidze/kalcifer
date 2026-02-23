defmodule Kalcifer.Repo.Migrations.CreateCustomers do
  use Ecto.Migration

  def change do
    create table(:customers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :restrict), null: false
      add :external_id, :string, null: false
      add :email, :string
      add :phone, :string
      add :name, :string
      add :properties, :map, default: %{}
      add :tags, {:array, :string}, default: []
      add :preferences, :map, default: %{}
      add :last_seen_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:customers, [:tenant_id, :external_id])
    create index(:customers, [:tenant_id])
    create index(:customers, [:email])
  end
end
