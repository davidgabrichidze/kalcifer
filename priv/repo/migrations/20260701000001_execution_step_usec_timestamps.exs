defmodule Kalcifer.Repo.Migrations.ExecutionStepUsecTimestamps do
  use Ecto.Migration

  # Second-precision timestamps made step ordering unstable when several
  # nodes execute within the same second.
  def change do
    alter table(:execution_steps) do
      modify :started_at, :utc_datetime_usec, null: false, from: {:utc_datetime, null: false}
      modify :completed_at, :utc_datetime_usec, from: :utc_datetime
    end
  end
end
