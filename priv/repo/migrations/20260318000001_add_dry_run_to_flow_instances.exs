defmodule Kalcifer.Repo.Migrations.AddDryRunToFlowInstances do
  use Ecto.Migration

  def change do
    alter table(:flow_instances) do
      add :dry_run, :boolean, default: false, null: false
    end
  end
end
