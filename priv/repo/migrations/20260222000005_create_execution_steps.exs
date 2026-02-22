defmodule Kalcifer.Repo.Migrations.CreateExecutionSteps do
  use Ecto.Migration

  def change do
    create table(:execution_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :instance_id, references(:journey_instances, type: :binary_id, on_delete: :delete_all),
        null: false

      add :node_id, :string, null: false
      add :node_type, :string, null: false
      add :version_number, :integer, null: false
      add :status, :string, null: false, default: "started"
      add :input, :map
      add :output, :map
      add :error, :map
      add :started_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:execution_steps, [:instance_id, :started_at])
  end
end
