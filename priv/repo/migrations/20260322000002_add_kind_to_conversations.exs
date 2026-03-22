defmodule Kalcifer.Repo.Migrations.AddKindToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :kind, :string
      add :entity_type, :string
      add :entity_id, :binary_id
    end

    create index(:conversations, [:kind])
    create index(:conversations, [:entity_type, :entity_id])
  end
end
