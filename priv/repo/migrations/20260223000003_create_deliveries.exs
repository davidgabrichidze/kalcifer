defmodule Kalcifer.Repo.Migrations.CreateDeliveries do
  use Ecto.Migration

  def change do
    create table(:deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :instance_id, references(:flow_instances, type: :binary_id, on_delete: :nilify_all)
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :restrict), null: false
      add :step_id, :binary_id
      add :channel, :string, null: false
      add :recipient, :map, null: false
      add :message, :map, default: %{}
      add :provider, :string
      add :provider_message_id, :string
      add :status, :string, null: false, default: "pending"
      add :error, :text
      add :sent_at, :utc_datetime
      add :delivered_at, :utc_datetime
      add :failed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:deliveries, [:instance_id])
    create index(:deliveries, [:tenant_id])
    create index(:deliveries, [:tenant_id, :channel, :status])
    create index(:deliveries, [:provider_message_id])
  end
end
