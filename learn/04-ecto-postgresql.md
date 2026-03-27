# Ecto & PostgreSQL — Data Layer

## Context: How Kalcifer Uses Ecto

Ecto is NOT an ORM. It's a data mapping and query toolkit. The distinction matters: ORMs hide SQL behind objects and magic methods. Ecto gives you explicit queries, explicit changesets (validation/transformation pipelines), and explicit schemas. Nothing happens implicitly.

Kalcifer stores all persistent state in PostgreSQL via Ecto: flows, versions, instances, execution steps, tenants, customers, journeys, deliveries, and AI conversations. The database is the source of truth — GenServer state is reconstructed from it on restart.

## Ecto's Four Main Components

### 1. Repo — The Database Connection

```elixir
defmodule Kalcifer.Repo do
  use Ecto.Repo,
    otp_app: :kalcifer,
    adapter: Ecto.Adapters.Postgres

  # Repo is a module you call directly — not an instance
end

# Usage everywhere in the codebase:
Kalcifer.Repo.all(Flow)                    # SELECT * FROM flows
Kalcifer.Repo.get!(Flow, id)               # SELECT * FROM flows WHERE id = $1 (raises on miss)
Kalcifer.Repo.get(Flow, id)                # Same but returns nil on miss
Kalcifer.Repo.insert(changeset)            # INSERT
Kalcifer.Repo.update(changeset)            # UPDATE
Kalcifer.Repo.delete(record)               # DELETE
Kalcifer.Repo.one(query)                   # Expects exactly one result
```

**Underwater Rock**: `Repo.get!` raises `Ecto.NoResultsError`. In controllers, this triggers a 404 via Phoenix error handling. In GenServers, it crashes the process (which the supervisor restarts). Both are intentional patterns in Kalcifer.

### 2. Schema — Data Structure Definition

```elixir
defmodule Kalcifer.Flows.Flow do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "flows" do
    field :name, :string
    field :status, :string, default: "draft"
    field :description, :string
    field :metadata, :map, default: %{}

    belongs_to :tenant, Kalcifer.Tenants.Tenant
    has_many :versions, Kalcifer.Flows.FlowVersion
    has_many :instances, Kalcifer.Flows.FlowInstance

    timestamps()
  end

  def changeset(flow, attrs) do
    flow
    |> cast(attrs, [:name, :status, :description, :metadata])
    |> validate_required([:name])
    |> validate_inclusion(:status, ["draft", "active", "paused", "archived"])
    |> validate_length(:name, max: 255)
  end
end
```

**Key Kalcifer conventions:**
- `@primary_key {:id, :binary_id, autogenerate: true}` — UUIDs, not auto-incrementing integers. This matters for distributed systems and avoiding sequential ID enumeration attacks.
- `@timestamps_opts [type: :utc_datetime]` — Always UTC, never local time.
- Status as strings, not PostgreSQL enums. Why? PG enums are hard to modify in migrations (adding values requires ALTER TYPE). Strings with Ecto validation are more flexible.

### 3. Changeset — Validation and Transformation

Changesets are Ecto's killer feature. They validate and transform data BEFORE it hits the database. Think of them as a pipeline that produces either valid data or a list of errors.

```elixir
# Creating a changeset from params
changeset = Flow.changeset(%Flow{}, %{
  "name" => "Welcome Campaign",
  "status" => "active"
})

# Inspecting validity
changeset.valid?  # true or false
changeset.errors  # [name: {"can't be blank", [validation: :required]}]

# Changesets compose
def create_flow(tenant, attrs) do
  %Flow{}
  |> Flow.changeset(attrs)
  |> Ecto.Changeset.put_assoc(:tenant, tenant)
  |> Repo.insert()
end

# Conditional validation
def status_changeset(flow, new_status) do
  flow
  |> change(%{status: new_status})
  |> validate_status_transition(flow.status, new_status)
end

defp validate_status_transition(changeset, "draft", "active"), do: changeset
defp validate_status_transition(changeset, "active", "paused"), do: changeset
defp validate_status_transition(changeset, "paused", "active"), do: changeset
defp validate_status_transition(changeset, _from, _to) do
  add_error(changeset, :status, "invalid transition")
end
```

**Underwater Rock**: Changesets are NOT applied until you call `Repo.insert/update/delete`. You can build, inspect, and compose changesets without touching the database. This makes them perfect for multi-step validation.

**Underwater Rock**: `cast/3` only allows the fields you explicitly list. Unknown fields are silently dropped. This is mass-assignment protection built into the framework.

### 4. Query — Composable SQL Builder

```elixir
import Ecto.Query

# Basic query
query = from f in Flow,
  where: f.tenant_id == ^tenant_id,
  where: f.status == "active",
  order_by: [desc: f.inserted_at],
  limit: 20

flows = Repo.all(query)

# Composable queries (Kalcifer pattern)
defmodule Kalcifer.Flows do
  def list_flows(tenant_id, params \\ %{}) do
    Flow
    |> where([f], f.tenant_id == ^tenant_id)
    |> maybe_filter_status(params["status"])
    |> maybe_search(params["search"])
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status) do
    where(query, [f], f.status == ^status)
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, term) do
    where(query, [f], ilike(f.name, ^"%#{term}%"))
  end
end
```

**The `^` pin operator in queries**: `^tenant_id` means "use the value of the variable `tenant_id`". Without `^`, Ecto treats it as a column reference. This is Elixir's pin operator repurposed for query interpolation — and it's safe from SQL injection because it uses parameterized queries.

### Preloading Associations

```elixir
# N+1 problem? Preload explicitly
flow = Repo.get!(Flow, id) |> Repo.preload(:versions)
flow.versions  # loaded

# Preload in query
flows = from(f in Flow, preload: [:versions]) |> Repo.all()

# Preload with conditions
flow = Repo.get!(Flow, id)
  |> Repo.preload(versions: from(v in FlowVersion, order_by: [desc: v.version_number]))
```

**Underwater Rock**: Ecto NEVER lazy-loads associations. Accessing `flow.versions` without preloading doesn't trigger a query — it returns `#Ecto.Association.NotLoaded`. This eliminates N+1 queries by making them impossible to create accidentally.

## Migrations

```elixir
defmodule Kalcifer.Repo.Migrations.CreateFlows do
  use Ecto.Migration

  def change do
    create table(:flows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :description, :text
      add :metadata, :map, default: %{}
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:flows, [:tenant_id])
    create index(:flows, [:status])
    create index(:flows, [:tenant_id, :status])
  end
end
```

**Key patterns in Kalcifer migrations:**
- `primary_key: false` + explicit `:binary_id` primary key (UUIDs)
- `on_delete: :delete_all` for tenant cascade (delete tenant → delete all their flows)
- Composite indexes for common query patterns (`tenant_id + status`)
- `type: :utc_datetime` for all timestamps

**Underwater Rock**: Use `change/0` for reversible migrations (Ecto can infer the rollback). Use `up/0` and `down/0` for complex migrations that can't be auto-reversed (data migrations, custom SQL).

## Ecto.Multi — Transactional Operations

When you need multiple database operations to succeed or fail together:

```elixir
defmodule Kalcifer.Flows do
  def activate_flow(tenant_id, flow_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:flow, fn repo, _ ->
      case repo.get_by(Flow, id: flow_id, tenant_id: tenant_id) do
        nil -> {:error, :not_found}
        flow -> {:ok, flow}
      end
    end)
    |> Ecto.Multi.run(:version, fn repo, %{flow: flow} ->
      case repo.get_by(FlowVersion, flow_id: flow.id, status: "draft") do
        nil -> {:error, :no_draft_version}
        version -> {:ok, version}
      end
    end)
    |> Ecto.Multi.update(:activate_flow, fn %{flow: flow} ->
      Flow.status_changeset(flow, "active")
    end)
    |> Ecto.Multi.update(:activate_version, fn %{version: version} ->
      FlowVersion.status_changeset(version, "active")
    end)
    |> Repo.transaction()
  end
end

# Returns {:ok, %{flow: flow, version: version, ...}} or {:error, failed_step, changeset, changes_so_far}
```

**Why Multi instead of Repo.transaction with anonymous function?** Multi gives you named steps, each step can reference previous steps' results, and the error tells you WHICH step failed.

## SQL Sandbox — Test Isolation

```elixir
# In test_helper.exs
Ecto.Adapters.SQL.Sandbox.mode(Kalcifer.Repo, :manual)

# In test setup (via ConnCase or DataCase)
setup tags do
  Kalcifer.DataCase.setup_sandbox(tags)
  :ok
end

# setup_sandbox wraps each test in a DB transaction that rolls back after the test
# This means tests can run concurrently without interfering with each other
```

**Underwater Rock**: SQL Sandbox works by wrapping each test in a transaction. But GenServer processes started during tests run in their own process — they can't see the test's transaction! Solution: explicitly allow the GenServer's process to share the test's connection:

```elixir
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Kalcifer.Repo)
  Ecto.Adapters.SQL.Sandbox.mode(Kalcifer.Repo, {:shared, self()})
end
```

This is a common gotcha in Kalcifer tests because FlowServer GenServers need database access.

## Multi-Tenancy Pattern

Every query in Kalcifer is scoped to a tenant:

```elixir
# Context functions always take tenant_id as first parameter
def list_flows(tenant_id) do
  Flow
  |> where([f], f.tenant_id == ^tenant_id)
  |> Repo.all()
end

# Never expose cross-tenant queries to the API layer
# The API auth plug extracts tenant from the API key
# Controllers pass tenant_id to context functions
```

**Underwater Rock**: There's no automatic tenant scoping. Every query MUST explicitly filter by tenant_id. Forgetting this leaks data across tenants. Some teams add a custom `Repo` wrapper that auto-scopes, but Kalcifer uses explicit scoping in context functions.

## JSON and Map Fields

PostgreSQL's JSONB type maps to Ecto's `:map` type:

```elixir
# Schema
field :graph, :map  # Stored as JSONB in PostgreSQL
field :context, :map
field :metadata, :map

# Usage — these are regular Elixir maps
flow_version.graph["nodes"]  # Access JSON structure
flow_version.graph["edges"]

# Querying JSONB (PostgreSQL-specific)
from i in FlowInstance,
  where: fragment("? ->> ? = ?", i.context, "_customer_id", ^customer_id)
```

**Underwater Rock**: JSONB fields are schemaless — Ecto won't validate their structure. Kalcifer uses NimbleOptions and custom validation in node modules to validate graph JSON structure.

## Performance Considerations

1. **Connection pooling**: Ecto uses DBConnection pool. Default 10 in dev, configurable in prod via `DATABASE_POOL_SIZE`. If you see "connection not available" errors, increase pool size.

2. **Preload vs Join**: Preload fires separate queries. Join embeds data in one query. For simple associations, preload is fine. For complex queries with conditions on associations, use join.

3. **Streaming large result sets**: `Repo.stream/2` with `Repo.transaction/1` for memory-efficient processing of large datasets.

4. **Prepared statements**: Ecto uses prepared statements by default. Repeated queries with different parameters reuse the same plan. This is why parameterized queries (`^variable`) are both safe AND fast.

## Recommended Resources

- "Programming Ecto" by Darin Wilson and Eric Meadows-Jönsson (the definitive book)
- Ecto official documentation: hexdocs.pm/ecto
- Ecto query documentation: hexdocs.pm/ecto/Ecto.Query.html
- PostgreSQL JSONB with Ecto: hexdocs.pm/ecto/schemaless-queries.html
