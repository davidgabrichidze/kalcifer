defmodule Kalcifer.Repo.Migrations.CreateJourneyVersions do
  use Ecto.Migration

  def change do
    create table(:journey_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :journey_id, references(:journeys, type: :binary_id, on_delete: :delete_all),
        null: false

      add :version_number, :integer, null: false
      add :graph, :map, null: false
      add :status, :string, null: false, default: "draft"
      add :node_mapping, :map
      add :migration_strategy, :string
      add :migration_config, :map
      add :changelog, :text
      add :published_by, :binary_id
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:journey_versions, [:journey_id, :version_number])
  end
end
