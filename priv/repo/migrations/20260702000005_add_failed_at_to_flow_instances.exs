defmodule Kalcifer.Repo.Migrations.AddFailedAtToFlowInstances do
  use Ecto.Migration

  @moduledoc """
  Instances had no failure timestamp, so the daily analytics rollup
  attributed failures by `updated_at` — which drifts whenever the row is
  touched again (recovery sweep, migration, cleanup), silently
  re-dating or losing the failure. Add a dedicated `failed_at` stamped
  once at the failed transition.
  """

  def change do
    alter table(:flow_instances) do
      add :failed_at, :utc_datetime
    end
  end
end
