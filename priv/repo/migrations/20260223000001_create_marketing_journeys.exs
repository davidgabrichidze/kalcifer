defmodule Kalcifer.Repo.Migrations.CreateMarketingJourneys do
  use Ecto.Migration

  def change do
    create table(:journeys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :restrict), null: false
      add :flow_id, references(:flows, type: :binary_id, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "draft"
      add :goal_config, :map, default: %{}
      add :schedule, :map, default: %{}
      add :audience_criteria, :map, default: %{}
      add :tags, {:array, :string}, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:journeys, [:tenant_id])
    create index(:journeys, [:tenant_id, :status])
    create index(:journeys, [:flow_id])
    create index(:journeys, [:tags], using: :gin)
  end
end
