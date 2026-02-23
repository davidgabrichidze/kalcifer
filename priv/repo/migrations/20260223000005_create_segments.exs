defmodule Kalcifer.Repo.Migrations.CreateSegments do
  use Ecto.Migration

  def change do
    create table(:segments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :description, :text
      add :type, :string, null: false, default: "dynamic"
      add :rules, {:array, :map}, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:segments, [:tenant_id])
  end
end
