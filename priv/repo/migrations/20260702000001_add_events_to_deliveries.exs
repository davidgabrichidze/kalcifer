defmodule Kalcifer.Repo.Migrations.AddEventsToDeliveries do
  use Ecto.Migration

  def change do
    alter table(:deliveries) do
      add :events, {:array, :map}, default: [], null: false
    end
  end
end
