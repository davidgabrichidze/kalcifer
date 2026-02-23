defmodule Kalcifer.Repo.Migrations.CreateAnalyticsTables do
  use Ecto.Migration

  def change do
    create table(:flow_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :flow_id, references(:flows, type: :binary_id, on_delete: :delete_all), null: false
      add :version_number, :integer, null: false
      add :date, :date, null: false
      add :entered, :integer, default: 0
      add :completed, :integer, default: 0
      add :failed, :integer, default: 0
      add :exited, :integer, default: 0
      add :avg_completion_time_seconds, :float

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flow_stats, [:flow_id, :version_number, :date])
    create index(:flow_stats, [:flow_id])

    create table(:node_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :flow_id, references(:flows, type: :binary_id, on_delete: :delete_all), null: false
      add :version_number, :integer, null: false
      add :node_id, :string, null: false
      add :date, :date, null: false
      add :executed, :integer, default: 0
      add :completed, :integer, default: 0
      add :failed, :integer, default: 0
      add :branch_counts, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:node_stats, [:flow_id, :version_number, :node_id, :date])
    create index(:node_stats, [:flow_id])

    create table(:conversions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :flow_id, references(:flows, type: :binary_id, on_delete: :delete_all), null: false

      add :instance_id, references(:flow_instances, type: :binary_id, on_delete: :delete_all),
        null: false

      add :customer_id, :string, null: false
      add :conversion_type, :string, null: false
      add :value, :float
      add :metadata, :map, default: %{}
      add :converted_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:conversions, [:flow_id])
    create index(:conversions, [:instance_id])
    create index(:conversions, [:customer_id])
    create index(:conversions, [:converted_at])
  end
end
