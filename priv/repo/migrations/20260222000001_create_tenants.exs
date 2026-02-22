defmodule Kalcifer.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  def change do
    create table(:tenants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :api_key_hash, :string, null: false
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenants, [:api_key_hash])
    create unique_index(:tenants, [:name])
  end
end
