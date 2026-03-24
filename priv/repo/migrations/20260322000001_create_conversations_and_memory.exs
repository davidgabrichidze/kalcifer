defmodule Kalcifer.Repo.Migrations.CreateConversationsAndMemory do
  use Ecto.Migration

  def change do
    # Conversations — persisted chat sessions
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :status, :string, default: "active", null: false
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:tenant_id])
    create index(:conversations, [:status])

    # Conversation messages — individual messages in a conversation
    create table(:conversation_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false
      add :content, :text, null: false
      add :tool_calls, :map

      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:conversation_messages, [:conversation_id])

    # Operator memory — persistent knowledge per tenant
    create table(:operator_memories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :value, :text, null: false
      add :category, :string, default: "general", null: false
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:operator_memories, [:tenant_id, :key])
    create index(:operator_memories, [:tenant_id, :category])
  end
end
