defmodule Kalcifer.Repo.Migrations.CreateAuditLog do
  use Ecto.Migration

  def change do
    create table(:audit_log, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :actor, :string, null: false
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :string
      add :details, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_log, [:tenant_id, :inserted_at])
    create index(:audit_log, [:resource_type, :resource_id])
  end
end
