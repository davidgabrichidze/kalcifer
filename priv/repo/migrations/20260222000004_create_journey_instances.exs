defmodule Kalcifer.Repo.Migrations.CreateJourneyInstances do
  use Ecto.Migration

  def change do
    create table(:journey_instances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :journey_id, references(:journeys, type: :binary_id, on_delete: :restrict), null: false
      add :version_number, :integer, null: false
      add :customer_id, :string, null: false
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :restrict), null: false
      add :status, :string, null: false, default: "running"
      add :current_nodes, {:array, :string}, default: []
      add :context, :map, default: %{}
      add :entered_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :exited_at, :utc_datetime
      add :exit_reason, :string
      add :migrated_from_version, :integer
      add :migrated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:journey_instances, [:tenant_id])

    # Partial indexes for performance-critical queries
    create index(:journey_instances, [:journey_id, :customer_id],
             where: "status = 'running'",
             name: :journey_instances_running_customer
           )

    create index(:journey_instances, [:status],
             where: "status IN ('running', 'waiting')",
             name: :journey_instances_active
           )

    create index(:journey_instances, [:journey_id, :version_number],
             where: "status IN ('running', 'waiting')",
             name: :journey_instances_version_active
           )
  end
end
