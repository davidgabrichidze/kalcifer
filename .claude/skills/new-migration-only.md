# /new-migration-only — Create a standalone migration

For schema alterations, new indexes, constraints, or data migrations (no new schema module needed).

## Steps

### 1. Generate migration file

Determine the next timestamp. Check existing migrations in `priv/repo/migrations/` for the latest.
Use format: `YYYYMMDDHHMMSS`.

File: `priv/repo/migrations/{timestamp}_{description}.exs`

### 2. Write migration

```elixir
defmodule Kalcifer.Repo.Migrations.{PascalCaseDescription} do
  use Ecto.Migration

  def change do
    # Examples:

    # Add column
    alter table(:table_name) do
      add :new_field, :string
      add :config, :map, default: %{}
    end

    # Add index
    create index(:table_name, [:field1, :field2])
    create unique_index(:table_name, [:tenant_id, :name], name: :table_name_tenant_name_idx)

    # Add foreign key
    alter table(:table_name) do
      add :other_id, references(:other_table, type: :binary_id, on_delete: :delete_all)
    end
  end
end
```

**Conventions**:
- Use `change/0` for reversible migrations (preferred)
- Use `up/0` + `down/0` only for irreversible operations (data migrations, dropping columns)
- Foreign keys always use `type: :binary_id`
- Index names: `{table}_{fields}_idx` or `{table}_{fields}_index`
- For unique constraints, use `create unique_index` (not DB-level constraints)

### 3. Run and verify

```bash
mix ecto.migrate
mix ecto.rollback
mix ecto.migrate
mix test --trace
```

The rollback + re-migrate confirms the migration is properly reversible.
