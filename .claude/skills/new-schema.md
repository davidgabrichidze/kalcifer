# /new-schema — Create a new Ecto schema with migration and factory

The user provides: schema name, fields, associations.

## Steps

### 1. Create the migration

File: `priv/repo/migrations/{timestamp}_create_{table_name}.exs`

Generate timestamp with: `Mix.Utils.extract_stale/2` pattern or use current datetime.
Format: `YYYYMMDDHHMMSS`

```elixir
defmodule Kalcifer.Repo.Migrations.Create{PluralPascalCase} do
  use Ecto.Migration

  def change do
    create table(:{table_name}, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      # Add fields here
      # add :name, :string, null: false
      # add :status, :string, null: false, default: "draft"
      # add :config, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    # Add indexes
    create index(:{table_name}, [:tenant_id])
  end
end
```

**Conventions**:
- Always use `primary_key: false` + `add :id, :binary_id, primary_key: true`
- Always use `timestamps(type: :utc_datetime)`
- Status fields are `:string` (NOT Postgres enums)
- JSON/map fields use `:map` type
- Always add `tenant_id` FK for multi-tenant tables
- Foreign keys use `type: :binary_id`

### 2. Create the schema

File: `lib/kalcifer/flows/{snake_case_name}.ex` (or appropriate context directory)

```elixir
defmodule Kalcifer.Flows.{PascalCaseName} do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "{table_name}" do
    field :name, :string
    field :status, :string, default: "draft"

    belongs_to :tenant, Kalcifer.Tenants.Tenant
    # Add associations here

    timestamps(type: :utc_datetime)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:name, :status])
    |> validate_required([:name])
  end
end
```

**Conventions**:
- `@moduledoc false`
- `@primary_key {:id, :binary_id, autogenerate: true}`
- `@foreign_key_type :binary_id`
- Separate `changeset/2` for create and `update_changeset/2` if update has different validations
- Aliases alphabetically ordered

### 3. Add factory

Edit `test/support/factory.ex`. Add a new factory function:

```elixir
def {snake_case_name}_factory do
  %Kalcifer.Flows.{PascalCaseName}{
    name: sequence(:{snake_case_name}_name, &"{PascalCaseName} #{&1}"),
    status: "draft",
    tenant: build(:tenant)
  }
end
```

Add the alias to the alias list (alphabetically ordered!).

### 4. Run migration and verify

```bash
mix ecto.migrate
mix test --trace
mix compile --warnings-as-errors
mix format
mix credo --strict
```
