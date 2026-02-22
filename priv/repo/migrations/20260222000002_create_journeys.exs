defmodule Kalcifer.Repo.Migrations.CreateJourneys do
  use Ecto.Migration

  def change do
    create table(:journeys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "draft"
      add :active_version_id, :binary_id
      add :entry_config, :map, default: %{}
      add :exit_criteria, :map, default: %{}
      add :frequency_cap, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:journeys, [:tenant_id])
    create index(:journeys, [:tenant_id, :status])
  end
end
