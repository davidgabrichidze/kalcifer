# Production Concerns — Deployment, Clustering, Observability

## Context: Running Kalcifer in Production

Moving from `mix phx.server` on localhost to a multi-node production deployment introduces concerns that don't exist in development: clustering (multiple BEAM nodes working together), structured logging for log aggregation, telemetry for metrics/alerting, release packaging, health checks, and operational recovery patterns.

## Elixir Releases

Elixir releases package your application into a self-contained directory with: compiled BEAM bytecode, the Erlang runtime, configuration, and boot scripts. No Elixir or Erlang installation needed on the target machine.

```bash
# Build a release
MIX_ENV=prod mix release

# Start the release
_build/prod/rel/kalcifer/bin/kalcifer start

# Run migrations (via Kalcifer.Release module)
_build/prod/rel/kalcifer/bin/kalcifer eval "Kalcifer.Release.migrate()"
```

### Runtime Configuration (runtime.exs)

```elixir
# config/runtime.exs — evaluated at APPLICATION START, not compile time
import Config

if config_env() == :prod do
  database_url = System.get_env("DATABASE_URL") ||
    raise "DATABASE_URL environment variable is not set"

  config :kalcifer, Kalcifer.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE") || "20"),
    ssl: System.get_env("DATABASE_SSL") == "true"

  secret_key_base = System.get_env("SECRET_KEY_BASE") ||
    raise "SECRET_KEY_BASE environment variable is not set"

  config :kalcifer, KalciferWeb.Endpoint,
    server: true,
    http: [port: String.to_integer(System.get_env("PORT") || "4500")]

  # AI configuration
  if api_key = System.get_env("ANTHROPIC_API_KEY") do
    config :kalcifer, :ai, api_key: api_key
  end
end
```

**Underwater Rock**: `config.exs`, `dev.exs`, `test.exs` are evaluated at COMPILE time. `runtime.exs` is evaluated at APPLICATION START. Environment variables in production MUST go in `runtime.exs`. Putting `System.get_env` in `config.exs` reads the build machine's env, not the production server's.

**Underwater Rock**: `Application.compile_env/3` reads config at compile time and burns it into the module. `Application.fetch_env/2` reads at runtime. Use compile_env for things that never change (adapter modules), fetch_env for things that might change between deployments (URLs, keys).

## Clustering

### Why Cluster?
A single BEAM node handles thousands of concurrent flow instances. But for high availability and horizontal scaling, you need multiple nodes. Clustering enables: PubSub messages to reach FlowServers on any node, Oban job distribution across nodes, and no single point of failure.

### dns_cluster (Kubernetes-Native)

```elixir
# In application.ex supervision tree
{DNSCluster, query: System.get_env("DNS_CLUSTER_QUERY")}

# In Kubernetes, set:
# DNS_CLUSTER_QUERY=kalcifer-headless.default.svc.cluster.local
# This resolves to all pod IPs → BEAM nodes connect automatically
```

### libcluster (Flexible Strategies)

```elixir
# config/prod.exs
config :libcluster,
  topologies: [
    k8s: [
      strategy: Cluster.Strategy.Kubernetes.DNS,
      config: [
        service: "kalcifer-headless",
        application_name: "kalcifer"
      ]
    ]
  ]
```

### What Clustering Gives You

**Phoenix.PubSub**: Messages broadcast on one node reach subscribers on all nodes. When EventRouter publishes an event, FlowServers on any node can receive it.

**Oban**: Jobs in PostgreSQL are picked up by any node. Cron jobs use leader election — only one node runs cron. If that node dies, another takes over.

**What clustering does NOT give you**: Process migration. A FlowServer started on node A stays on node A. If node A dies, RecoveryManager on another node restarts the instance from DB state.

### The Cluster-Aware Recovery Pattern

```
Node A running FlowServer(instance_123)
  → Node A crashes

Node B (still alive)
  → Doesn't know about instance_123 immediately
  → Oban jobs for instance_123 still in PostgreSQL
  → When ResumeFlowJob fires, it runs on Node B
  → Node B starts new FlowServer(instance_123) from DB state
  → Execution continues

OR: Node A restarts
  → RecoveryManager on Node A scans DB
  → Finds instance_123 in "waiting" status
  → Starts FlowServer(instance_123) locally
```

## Structured Logging

### logger_json

```elixir
# Production logging — structured JSON for log aggregation (ELK, Datadog, etc.)
config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Basic, []}

# Output looks like:
# {"time":"2026-03-27T10:15:30Z","level":"info","message":"Flow instance started",
#  "metadata":{"flow_id":"abc","instance_id":"def","tenant_id":"ghi","customer_id":"jkl"}}
```

### Metadata Propagation

```elixir
# In plugs — set request-level metadata
Logger.metadata(
  request_id: conn.assigns[:request_id],
  tenant_id: tenant.id
)

# In FlowServer — set instance-level metadata
Logger.metadata(
  flow_id: state.flow_id,
  instance_id: state.instance_id,
  customer_id: state.customer_id
)

# In node executor — set node-level metadata
Logger.metadata(node_id: node.id, node_type: node.type)

# All log messages from this process now include all metadata
Logger.info("Executing node")
# → {"message":"Executing node","flow_id":"abc","instance_id":"def","node_id":"n1","node_type":"send_email"}
```

**Why this matters**: When debugging a production issue, you can filter logs by instance_id to see the entire execution trace of a single flow instance across all nodes.

### LogCollector — Engine Room Dashboard

Kalcifer has a custom LogCollector and LogHandler that capture engine logs in memory for a real-time dashboard (Engine Room). This is separate from file/structured logging — it's for live operational visibility.

## Telemetry — Metrics and Monitoring

### The Telemetry Pattern

Telemetry is Elixir's standard metrics library. Code emits events, handlers process them (send to StatsD, Prometheus, Datadog, etc.).

```elixir
# Emitting telemetry events
:telemetry.execute(
  [:kalcifer, :engine, :node, :execute],
  %{duration: duration_ms},
  %{node_type: node_type, flow_id: flow_id, status: :completed}
)

# Attaching handlers (in application startup)
:telemetry.attach("node-execution-metrics",
  [:kalcifer, :engine, :node, :execute],
  &MyMetricsHandler.handle_event/4,
  nil
)
```

### Built-In Telemetry Events

Phoenix, Ecto, and Oban all emit telemetry:

```
[:phoenix, :endpoint, :stop]         — request completed (duration, status)
[:kalcifer, :repo, :query]           — database query (duration, query)
[:oban, :job, :stop]                 — job completed (worker, queue, duration)
[:oban, :job, :exception]            — job failed (worker, error)
```

### telemetry_poller — System Metrics

```elixir
# Periodically emits system metrics:
# - VM memory usage
# - Process count
# - Run queue length (if > 0, BEAM is overloaded)
# - Garbage collection stats

{:telemetry_poller, measurements: [
  {Kalcifer.Metrics, :engine_stats, []}  # Custom measurements
], period: 10_000}  # Every 10 seconds
```

## Health Checks

```elixir
# GET /api/v1/health — basic liveness
def index(conn, _params) do
  json(conn, %{status: "ok", version: Application.spec(:kalcifer, :vsn)})
end

# GET /api/v1/health/metrics — detailed readiness
def metrics(conn, _params) do
  json(conn, %{
    status: "ok",
    database: check_database(),
    oban: check_oban(),
    engine: %{
      active_instances: DynamicSupervisor.count_children(FlowSupervisor).active,
      registered_nodes: NodeRegistry.count()
    }
  })
end
```

**Kubernetes integration**: Use `/health` for liveness probes (is the process alive?) and `/health/metrics` for readiness probes (can the service handle traffic?). If the database is down, readiness should fail but liveness should pass (the process is alive, just can't serve requests yet).

## Environment Variables Reference

```bash
# Required in production
DATABASE_URL="postgresql://user:pass@host:5432/kalcifer_prod"
SECRET_KEY_BASE="generated-with-mix-phx-gen-secret"

# Optional
PORT=4500                          # HTTP port (default: 4500)
DATABASE_POOL_SIZE=20              # DB connection pool (default: 20)
DATABASE_SSL=true                  # Enable SSL for DB connection
DNS_CLUSTER_QUERY="kalcifer.svc"   # Kubernetes service discovery
ECTO_IPV6=true                     # Enable IPv6 for DB connections
PHX_SERVER=true                    # Start HTTP server (set in release)
ANTHROPIC_API_KEY="sk-ant-..."     # For AI node features
AUTH_SESSION_SECRET="..."          # For JWT session tokens
```

## Deployment Strategies

### Docker (Recommended)

```dockerfile
# Multi-stage build
FROM elixir:1.18-otp-28-alpine AS build
WORKDIR /app
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
COPY . .
RUN MIX_ENV=prod mix release

FROM alpine:3.19
COPY --from=build /app/_build/prod/rel/kalcifer ./kalcifer
CMD ["./kalcifer/bin/kalcifer", "start"]
```

### Release Tasks (Migrations)

```elixir
defmodule Kalcifer.Release do
  def migrate do
    Application.ensure_all_started(:kalcifer)
    Ecto.Migrator.run(Kalcifer.Repo, :up, all: true)
  end

  def rollback(version) do
    Application.ensure_all_started(:kalcifer)
    Ecto.Migrator.run(Kalcifer.Repo, :down, to: version)
  end
end

# Run before starting the app:
# ./kalcifer/bin/kalcifer eval "Kalcifer.Release.migrate()"
```

## Operational Patterns

### Graceful Shutdown

When a node is being drained (rolling deploy):
1. Stop accepting new HTTP requests (Bandit drains existing connections)
2. Stop picking up new Oban jobs (Oban's graceful shutdown)
3. FlowServer processes save state to DB before terminating (GenServer terminate/2)
4. After drain period, BEAM shuts down

### Blue-Green Deployments with Oban

Oban jobs are in PostgreSQL. During a blue-green deployment, both old and new versions can safely process jobs because they share the same database. Oban's locking prevents double processing.

**Underwater Rock**: If a new version changes a worker's args format, old version workers won't understand new version's jobs (and vice versa). Always make args changes backward-compatible, or drain the queue before switching.

### Database Connection Management

```
Production pool_size recommendations:
  - Small: 10-20 connections (< 1000 active instances)
  - Medium: 30-50 connections (1000-10000 instances)
  - Large: 50-100 connections (10000+ instances)

Each Oban queue also uses DB connections.
Rule of thumb: pool_size >= sum(oban_queue_sizes) + 10
```

**Underwater Rock**: PostgreSQL default max_connections is 100. With multiple Elixir nodes each requesting 20+ connections, you'll hit the limit. Use PgBouncer (connection pooler) in production, or increase max_connections in PostgreSQL config.

## Pre-Production Checklist

1. **mix precommit passes**: compile (no warnings), deps check, format check, all tests pass
2. **Credo strict**: `mix credo --strict` — no violations
3. **Dialyzer**: `mix dialyzer` — no type errors
4. **Database migrations**: reversible, tested up and down
5. **Environment variables**: all required vars documented and set
6. **Health endpoints**: /health and /health/metrics responding
7. **Log aggregation**: structured JSON logs flowing to centralized system
8. **Telemetry handlers**: key metrics (request duration, job duration, error rates) being collected
9. **Oban monitoring**: discarded job count alerting configured
10. **Circuit breaker thresholds**: set appropriately for each channel provider's SLA

## Recommended Resources

- "Adopting Elixir" by Ben Marx, José Valim, Bruce Tate (deployment chapter)
- Phoenix deployment guides: hexdocs.pm/phoenix/deployment.html
- Oban production guide: hexdocs.pm/oban/production.html
- Elixir release documentation: hexdocs.pm/mix/Mix.Tasks.Release.html
- "Real-Time Phoenix" by Stephen Bussey (PubSub and clustering chapters)
