# Kalcifer — CLAUDE.md

## What is this project?

Flow orchestration engine built on Elixir/OTP. The core engine is domain-agnostic ("Flow"); marketing automation ("Journey") is a layer on top.

## Tech stack

- Elixir ~> 1.17 / OTP 28, Phoenix 1.7 (API-only, no HTML/LiveView)
- PostgreSQL 16 (primary), Oban 2.18 (job queue), Bandit (HTTP server)
- ExMachina (factories), Mox (mocking), StreamData (property tests)

## Quick commands

```bash
mix setup                    # deps.get + ecto.create + ecto.migrate
mix phx.server               # dev server on localhost:4500
mix test --trace             # ALWAYS use --trace (shows test names)
mix precommit                # compile --warnings-as-errors + deps.unlock --check-unused + format --check + test
mix format                   # auto-format
mix credo --strict           # lint (strict mode is default in .credo.exs)
mix dialyzer                 # type check
```

## Ports

- Dev: 4500
- Test: 4502
- Do NOT use port 6000 (unsafe in browsers)

## Project structure

```
lib/kalcifer/                    # Core business logic
  flows.ex                       # Flow context (CRUD, lifecycle)
  marketing.ex                   # Journey context (marketing wrapper)
  tenants.ex                     # Multi-tenancy, API key hashing
  flows/                         # Schemas: Flow, FlowVersion, FlowInstance, FlowGraph, ExecutionStep
  marketing/journey.ex           # Journey schema
  engine/                        # Execution engine
    supervisor.ex                # Engine supervision tree (rest_for_one)
    flow_server.ex               # GenServer per active flow instance
    node_registry.ex             # ETS: string type → module mapping
    node_executor.ex             # Executes nodes
    graph_walker.ex              # Graph traversal
    event_router.ex              # Routes events to waiting flow instances
    recovery_manager.ex          # Crash recovery on boot
    duration.ex                  # "3d", "2h" → seconds parser
    nodes/behaviour.ex           # NodeBehaviour callbacks
    nodes/{trigger,condition,wait,end}/  # Node implementations by category
    nodes/action/{channel,data}/         # Action nodes split by subcategory
    jobs/resume_flow_job.ex      # Oban worker for delayed resume
    persistence/                 # InstanceStore, StepStore
lib/kalcifer_web/                # Phoenix API layer
  router.ex                      # /api/v1/* routes
  plugs/api_key_auth.ex          # Bearer token → tenant lookup
  controllers/                   # flow, journey, trigger, event, health
test/support/factory.ex          # ExMachina factories
```

## Architecture rules

### Domain naming
- Core engine uses "Flow" terminology, NOT "Journey" (Journey is the marketing wrapper)
- Node categories: `:trigger | :condition | :wait | :action | :end` (NOT BPMN jargon like "gateway")
- Two user types: "participant" (customer in flow) vs "operator" (marketer building flows). Never confuse these
- Operator notifications (Slack alerts, digests) are NOT flow graph nodes — they belong in a separate observability layer

### Patterns
- **Process-per-instance**: Each active FlowInstance gets a FlowServer GenServer via DynamicSupervisor
- **Plugin-style nodes**: NodeRegistry (ETS) maps string type → module. New nodes can register at runtime
- **Generic context**: Execution passes a `context` map; node results accumulate in `context.accumulated`
- **Status state machine**: draft → active ↔ paused → archived (both Flows and Journeys)

### Node system
- NodeBehaviour callbacks: `execute/2`, `resume/3` (optional), `validate/1` (optional), `config_schema/0`, `category/0`
- Execute returns: `{:completed, result}` | `{:branched, branch_key, result}` | `{:waiting, wait_config}` | `{:failed, reason}`
- 23 built-in nodes across 5 categories
- Registry keys are snake_case strings matching graph JSON type field (e.g. `"send_email"`, `"condition"`)

## Git conventions

Conventional commits format: `<type>: <description>`

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`

Examples:
```
feat: implement event routing for waiting flow instances
fix: correct duration parsing for fractional hours
test: add edge case tests for flow server resume
refactor: extract frequency cap helpers into separate module
docs: add CLAUDE.md with project conventions
```

## Coding conventions

### Naming
- Modules: `Kalcifer.Engine.Nodes.{Category}.{Name}` — no "Node" suffix (e.g. `FrequencyCap`, not `FrequencyCapNode`)
- Schemas: `Kalcifer.Flows.{SchemaName}` — binary_id PKs, status as strings (not PG enums)
- DB tables: `flows`, `flow_versions`, `flow_instances`, `execution_steps`
- Factory names: `:flow`, `:flow_version`, `:flow_instance`, `:execution_step`, `:tenant`, `:journey`

### Style (enforced by Credo strict)
- Max line length: 120 characters
- Aliases MUST be alphabetically ordered
- Numbers > 9999 must use underscores: `86_400` not `86400`
- No `@doc` on private functions (fails `--warnings-as-errors`). Use plain comments instead

### Testing
- Always run with `--trace`
- Oban testing mode: `:manual` in test.exs (jobs stored, not auto-executed)
- Recovery: `skip_recovery: true` in test config; tests call `RecoveryManager.recover()` manually when needed
- ETS-based registry: tests adding entries persist — use `>= N` assertions, not `== N`
- For FlowServer resume tests: use direct `GenServer.cast` instead of relying on Oban inline mode

## Authentication

API key auth via Bearer token:
- `Authorization: Bearer <raw_key>` → SHA256 hash → lookup tenant by `api_key_hash`
- Implemented in `KalciferWeb.Plugs.ApiKeyAuth`

## Database

- All PKs: `binary_id` (UUID)
- Timestamps: `utc_datetime`
- Migrations in `priv/repo/migrations/`
- Test DB supports partitioning via `MIX_TEST_PARTITION` env var

## Config highlights

- Oban queues: `flow_triggers: 10`, `delayed_resume: 20`, `maintenance: 5`
- Test config: Ecto SQL Sandbox, Oban manual mode, logger level `:warning`
- Production: reads `DATABASE_URL`, `SECRET_KEY_BASE`, `PORT` from env vars
