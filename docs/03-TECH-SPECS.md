# Kalcifer — Technical Specifications

**Version**: 1.0
**Date**: 2026-02-22
**Status**: Draft

---

## 1. Technology Stack

### 1.1 Runtime & Framework

| Component | Technology | Version | Rationale |
|-----------|-----------|---------|-----------|
| Language | Elixir | ~> 1.17 | BEAM VM — lightweight processes, fault tolerance, hot code reload |
| Runtime | Erlang/OTP | ~> 27 | Supervision trees, gen_statem, distributed clustering |
| Web Framework | Phoenix | ~> 1.7 | Channels (WebSocket), PubSub, Endpoint, LiveDashboard |
| Database ORM | Ecto | ~> 3.12 | Migrations, changesets, multi-tenancy scoping, query composition |
| Job Processing | Oban | ~> 2.18 | PostgreSQL-backed, distributed, cron, unique jobs, observability |
| Data Pipeline | Broadway | ~> 1.1 | Batching, backpressure, rate limiting for ClickHouse writes |
| HTTP Client | Finch | ~> 0.19 | Connection pooling for ES, ClickHouse, external APIs |
| Telemetry | PromEx + OpenTelemetry | latest | Prometheus metrics, distributed tracing |
| Encryption | Cloak.Ecto | ~> 1.3 | Transparent field-level encryption for credentials |
| Auth | Guardian | ~> 2.3 | JWT token handling |

### 1.2 Data Stores

| Store | Technology | Version | Purpose |
|-------|-----------|---------|---------|
| Primary DB | PostgreSQL | 16+ | Journey definitions, execution state, tenants, config, Oban jobs |
| Search/Segments | Elasticsearch | 8.x | Customer profiles, segment evaluation |
| Analytics | ClickHouse | 24.x | Execution events, channel events, materialized aggregations |

### 1.3 Frontend

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Visual Editor | React + ReactFlow | Best-in-class flow editor, embeddable as Web Component |
| UI Framework | Tailwind CSS + Radix UI | Lightweight, accessible, themeable |
| State Management | Zustand | Simpler than Redux for editor state |
| API Client | TanStack Query | Caching, optimistic updates, WebSocket integration |
| Build Tool | Vite | Fast builds, library mode for Web Component output |
| Language | TypeScript | Type safety for complex editor logic |

**Note**: Frontend is a separate package, not coupled to Phoenix. Distributed as:
1. npm package (for embedding in React/Angular/Vue apps)
2. Web Component (for framework-agnostic embedding)
3. Standalone SPA (hosted by Phoenix in default deployment)

---

## 2. Project Structure

```
optio_flow/
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                      # Test + lint + typecheck
│   │   ├── chaos-test.yml              # Chaos testing suite (weekly + pre-release)
│   │   ├── load-test.yml               # Performance benchmarks (weekly + pre-release)
│   │   └── release.yml                 # Build & publish Docker image
│   └── CODEOWNERS
│
├── config/
│   ├── config.exs                      # Compile-time config
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs                     # Runtime config (env vars)
│
├── lib/
│   ├── optio_flow/                     # Business logic
│   │   ├── application.ex              # OTP application & supervision tree
│   │   ├── repo.ex                     # Ecto repo with tenant scoping
│   │   │
│   │   ├── tenants/                    # Multi-tenancy
│   │   │   ├── tenant.ex              # Schema
│   │   │   ├── tenant_context.ex      # Process dictionary tenant context
│   │   │   └── tenants.ex             # Context module
│   │   │
│   │   ├── journeys/                   # Journey definitions (CRUD)
│   │   │   ├── journey.ex             # Schema
│   │   │   ├── journey_graph.ex       # Graph validation (DAG check, orphan nodes)
│   │   │   ├── journey_version.ex     # Version schema (immutable snapshots)
│   │   │   └── journeys.ex            # Context module
│   │   │
│   │   ├── versioning/                 # Journey versioning & live migration
│   │   │   ├── version_manager.ex     # Create/publish/rollback versions
│   │   │   ├── version_differ.ex      # Structural diff between versions
│   │   │   ├── node_mapper.ex         # Auto + manual node mapping (old→new)
│   │   │   ├── migration_planner.ex   # Plan: strategy, batch size, rollout %
│   │   │   ├── migration_executor.ex  # Execute migration on running instances
│   │   │   ├── migration_monitor.ex   # Track progress, detect anomalies
│   │   │   └── ai_mapper.ex           # AI-assisted node mapping for complex diffs
│   │   │
│   │   ├── ai_designer/               # AI journey design (conversation + documents)
│   │   │   ├── designer.ex           # Main orchestrator
│   │   │   ├── conversation.ex       # Multi-turn state, context accumulation
│   │   │   ├── prompt_builder.ex     # System prompt + node catalog + few-shot
│   │   │   ├── graph_generator.ex    # LLM response → validated graph JSON
│   │   │   ├── document_parser.ex    # Excel/CSV/Word/PDF → structured intent
│   │   │   ├── suggestion_engine.ex  # Analytics-based optimization hints
│   │   │   └── providers/
│   │   │       ├── provider.ex       # @behaviour LLMProvider
│   │   │       ├── anthropic.ex      # Claude API
│   │   │       ├── openai.ex         # GPT-4 API
│   │   │       └── ollama.ex         # Self-hosted (Ollama / vLLM)
│   │   │
│   │   ├── engine/                     # Execution engine (OTP core)
│   │   │   ├── supervisor.ex          # Engine supervisor (rest_for_one)
│   │   │   ├── journey_supervisor.ex  # DynamicSupervisor for instances
│   │   │   ├── journey_server.ex      # GenServer per instance
│   │   │   ├── journey_state.ex       # State struct & transitions
│   │   │   ├── node_registry.ex       # Node type catalog (ETS)
│   │   │   ├── node_executor.ex       # Dispatch config → node module → execute
│   │   │   ├── event_router.ex        # Customer event routing (ETS + PubSub)
│   │   │   ├── frequency_cap.ex       # Cross-journey frequency enforcement
│   │   │   ├── recovery.ex            # Post-crash state recovery
│   │   │   ├── deduplication.ex       # Exactly-once channel send guard
│   │   │   │
│   │   │   ├── nodes/                 # Node implementations
│   │   │   │   ├── behaviour.ex       # @behaviour NodeBehaviour
│   │   │   │   ├── entry/
│   │   │   │   │   ├── segment_entry.ex
│   │   │   │   │   ├── event_entry.ex
│   │   │   │   │   └── webhook_entry.ex
│   │   │   │   ├── channel/
│   │   │   │   │   ├── send_email.ex
│   │   │   │   │   ├── send_sms.ex
│   │   │   │   │   ├── send_push.ex
│   │   │   │   │   ├── send_whatsapp.ex
│   │   │   │   │   └── call_webhook.ex
│   │   │   │   ├── logic/
│   │   │   │   │   ├── wait.ex
│   │   │   │   │   ├── wait_until.ex
│   │   │   │   │   ├── wait_for_event.ex
│   │   │   │   │   ├── condition.ex
│   │   │   │   │   ├── ab_split.ex
│   │   │   │   │   └── frequency_cap_node.ex
│   │   │   │   ├── data/
│   │   │   │   │   ├── update_profile.ex
│   │   │   │   │   ├── add_tag.ex
│   │   │   │   │   └── custom_code.ex
│   │   │   │   └── exit/
│   │   │   │       ├── goal_reached.ex
│   │   │   │       └── journey_exit.ex
│   │   │   │
│   │   │   └── persistence/           # Engine state persistence
│   │   │       ├── instance_store.ex  # journey_instances CRUD
│   │   │       └── step_store.ex      # execution_steps CRUD
│   │   │
│   │   ├── customers/                  # Customer profile abstraction
│   │   │   ├── profile_store.ex       # @behaviour ProfileStore
│   │   │   ├── elasticsearch_store.ex # Default implementation
│   │   │   └── segment_evaluator.ex   # Segment → ES query builder
│   │   │
│   │   ├── channels/                   # Channel provider abstraction
│   │   │   ├── email_provider.ex      # @behaviour
│   │   │   ├── sms_provider.ex        # @behaviour
│   │   │   ├── push_provider.ex       # @behaviour
│   │   │   ├── template_renderer.ex   # Variable substitution
│   │   │   └── providers/
│   │   │       ├── email/
│   │   │       │   ├── sendgrid.ex
│   │   │       │   ├── ses.ex
│   │   │       │   └── smtp.ex
│   │   │       ├── sms/
│   │   │       │   ├── twilio.ex
│   │   │       │   └── message_bird.ex
│   │   │       └── push/
│   │   │           ├── fcm.ex
│   │   │           └── apns.ex
│   │   │
│   │   ├── analytics/                  # ClickHouse analytics pipeline
│   │   │   ├── pipeline.ex            # Broadway pipeline definition
│   │   │   ├── event_producer.ex      # PG LISTEN producer
│   │   │   ├── event_processor.ex     # Transform for ClickHouse format
│   │   │   ├── clickhouse_writer.ex   # Batch HTTP insert
│   │   │   └── queries.ex            # Analytical query builders
│   │   │
│   │   ├── auth/                       # Authentication & authorization
│   │   │   ├── api_key.ex
│   │   │   ├── jwt.ex
│   │   │   └── rbac.ex
│   │   │
│   │   └── sandbox/                    # CustomCode node sandboxing
│   │       └── lua_runner.ex          # Luerl-based Lua sandbox
│   │
│   └── optio_flow_web/                 # Phoenix web layer
│       ├── endpoint.ex
│       ├── router.ex
│       ├── controllers/
│       │   ├── journey_controller.ex
│       │   ├── execution_controller.ex
│       │   ├── event_controller.ex
│       │   ├── webhook_controller.ex
│       │   ├── analytics_controller.ex
│       │   ├── customer_controller.ex
│       │   └── health_controller.ex
│       ├── channels/
│       │   ├── user_socket.ex
│       │   ├── journey_channel.ex
│       │   └── execution_channel.ex
│       ├── plugs/
│       │   ├── authenticate.ex
│       │   ├── rate_limit.ex
│       │   └── tenant_context.ex
│       └── views/ (or JSON modules)
│
├── priv/
│   ├── repo/migrations/                # Ecto migrations
│   └── clickhouse/                     # ClickHouse schema setup
│       ├── 001_execution_events.sql
│       ├── 002_channel_events.sql
│       └── 003_materialized_views.sql
│
├── test/
│   ├── optio_flow/
│   │   ├── engine/                     # Engine unit tests
│   │   │   ├── journey_server_test.exs
│   │   │   ├── node_executor_test.exs
│   │   │   ├── event_router_test.exs
│   │   │   ├── recovery_test.exs
│   │   │   └── nodes/                  # Per-node tests
│   │   ├── journeys/                   # CRUD tests
│   │   ├── channels/                   # Provider tests (with mocks)
│   │   └── analytics/                  # Pipeline tests
│   ├── optio_flow_web/                 # API tests
│   ├── property/                       # Property-based tests (StreamData)
│   │   ├── journey_graph_test.exs
│   │   ├── state_machine_test.exs
│   │   └── event_routing_test.exs
│   ├── chaos/                          # Chaos tests
│   │   ├── process_kill_test.exs
│   │   ├── db_disconnect_test.exs
│   │   └── network_partition_test.exs
│   ├── load/                           # Load/stress tests
│   │   ├── concurrent_journeys_test.exs
│   │   └── event_throughput_test.exs
│   ├── support/
│   │   ├── factory.ex                  # ExMachina factories
│   │   ├── channel_mock.ex             # Mock channel providers
│   │   └── fixtures/
│   └── test_helper.exs
│
├── frontend/                           # Separate frontend package
│   ├── package.json
│   ├── tsconfig.json
│   ├── vite.config.ts
│   ├── src/
│   │   ├── editor/                     # ReactFlow-based editor
│   │   │   ├── JourneyEditor.tsx       # Main editor component
│   │   │   ├── nodes/                  # Custom ReactFlow nodes
│   │   │   ├── edges/                  # Custom edges (conditional)
│   │   │   ├── panels/                 # Node config panels
│   │   │   ├── toolbar/                # Editor toolbar
│   │   │   └── validation.ts           # Client-side graph validation
│   │   ├── monitor/                    # Real-time monitoring views
│   │   │   ├── JourneyMonitor.tsx      # Live journey view
│   │   │   ├── CustomerTrace.tsx       # Individual customer trace
│   │   │   └── Analytics.tsx           # Dashboard
│   │   ├── api/                        # API client
│   │   │   ├── client.ts              # REST + WebSocket
│   │   │   └── hooks.ts              # TanStack Query hooks
│   │   ├── web-component.ts           # Web Component wrapper
│   │   └── index.ts                   # npm package entry
│   └── dist/                          # Build output
│       ├── optioflow-editor.js        # UMD bundle (Web Component)
│       └── optioflow-editor.es.js     # ES Module
│
├── docker/
│   ├── Dockerfile                     # Multi-stage Elixir release
│   ├── Dockerfile.dev                 # Development with hot reload
│   └── docker-compose.yml            # Full stack (PG + ES + CH + Kalcifer)
│
├── k8s/                               # Kubernetes manifests
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── hpa.yaml                       # Horizontal Pod Autoscaler
│
├── benchmarks/                        # Benchee performance benchmarks
│   ├── node_execution_bench.exs
│   ├── event_routing_bench.exs
│   └── persistence_bench.exs
│
├── mix.exs
├── mix.lock
├── .formatter.exs
├── .credo.exs                         # Credo static analysis config
├── .dialyzer_ignore.exs
├── LICENSE                            # Apache 2.0
└── README.md
```

---

## 3. API Specification

### 3.1 REST API

Base URL: `/api/v1`

#### Journeys

```
POST   /journeys                    Create journey (manual or from AI)
GET    /journeys                    List journeys (paginated, filtered)
GET    /journeys/:id                Get journey with current version graph
PUT    /journeys/:id                Update journey draft
DELETE /journeys/:id                Delete journey (draft only)
POST   /journeys/:id/activate       Activate journey (publish current draft version)
POST   /journeys/:id/pause          Pause journey (active → paused)
POST   /journeys/:id/resume         Resume journey (paused → active)
POST   /journeys/:id/archive        Archive journey (any → archived)
POST   /journeys/:id/duplicate      Clone journey as new draft
```

#### AI Designer

```
POST   /ai/conversations             Start new AI conversation
         Body: { journey_id?: "j1", message: "create a 30-day onboarding..." }
         Response: streaming SSE { graph, explanation, follow_up_questions }

POST   /ai/conversations/:id/message  Continue conversation
         Body: { message: "add SMS fallback" }
         Response: streaming SSE { updated_graph, diff, explanation }

POST   /ai/upload                     Upload document → generate journey
         Body: multipart { file: campaign.xlsx, instructions?: "..." }
         Response: { graph, explanation, detected_steps: [...] }

POST   /ai/explain                    Explain existing journey in natural language
         Body: { journey_id: "j1" }
         Response: { explanation: "This journey..." }

POST   /ai/suggest                    Get AI optimization suggestions
         Body: { journey_id: "j1" }
         Response: { suggestions: [{ type, description, proposed_diff }] }
```

#### Versioning

```
GET    /journeys/:id/versions                List all versions
GET    /journeys/:id/versions/:v             Get specific version (with graph)
POST   /journeys/:id/versions                Create new draft version
         Body: { graph: {...}, changelog: "Added SMS step" }

POST   /journeys/:id/versions/:v/publish     Publish version with migration strategy
         Body: {
           migration_strategy: "migrate_all" | "new_entries_only" | "gradual",
           migration_config: { rollout_percent: 10, batch_size: 1000 },
           node_mapping: { "old_node_1": "new_node_1", ... }
         }

GET    /journeys/:id/versions/:v/diff/:v2    Diff between two versions
         Response: { added_nodes, removed_nodes, changed_nodes, changed_edges }

POST   /journeys/:id/versions/:v/rollback    Rollback to this version
         Body: { migration_strategy: "migrate_all" }

POST   /ai/node-mapping                       AI-assisted node mapping
         Body: { old_version: {...}, new_version: {...} }
         Response: { suggested_mapping: {...}, confidence: {...} }
```

#### Migrations

```
GET    /journeys/:id/migrations              List migrations (history)
GET    /migrations/:id                        Migration detail + progress
POST   /migrations/:id/pause                  Pause active migration
POST   /migrations/:id/resume                 Resume paused migration
POST   /migrations/:id/abort                  Abort and rollback migration

GET    /journeys/:id/instances/by-version     Instance count per version
         Response: { "v1": 12340, "v2": 37660 }
```

#### Execution

```
POST   /journeys/:id/trigger        Manually enroll customer(s)
         Body: { customer_ids: ["c1", "c2"] }

GET    /journeys/:id/instances       List active instances (paginated, filterable by version)
GET    /instances/:id                Get instance detail with step history + version transitions
POST   /instances/:id/pause          Pause specific instance
POST   /instances/:id/resume         Resume specific instance
POST   /instances/:id/exit           Force exit specific instance
```

#### Events

```
POST   /events                       Ingest customer event
         Body: { customer_id: "c123", event_type: "purchase", data: {...} }

POST   /events/batch                 Ingest batch of events
         Body: { events: [...] }
```

#### Webhooks (entry triggers)

```
POST   /webhooks/:journey_id         Journey-specific webhook entry
         Body: { customer_id: "c123", data: {...} }
```

#### Analytics

```
GET    /journeys/:id/analytics       Journey-level metrics
GET    /journeys/:id/funnel          Node-by-node funnel
GET    /journeys/:id/nodes/:nid/metrics   Per-node metrics
GET    /instances/:id/trace          Customer journey trace (timeline)
GET    /analytics/channels            Cross-journey channel metrics
```

#### Customers

```
GET    /customers/:id/profile        Get customer profile
PATCH  /customers/:id/profile        Update customer attributes
GET    /customers/:id/journeys       List customer's active journeys
```

#### System

```
GET    /health                       Health check (PG, ES, CH connectivity)
GET    /health/ready                 Readiness (all systems operational)
GET    /metrics                      Prometheus metrics
GET    /info                         System info (version, uptime, stats)
```

### 3.2 WebSocket API

Channel: `journey:{journey_id}`

```
# Join channel to receive real-time updates for a journey
{ topic: "journey:j123", event: "phx_join" }

# Server pushes:
{ event: "node_counts", payload: { node_id: count, ... } }          # Every 1s
{ event: "instance_event", payload: { instance_id, node_id, type } } # Per event
{ event: "journey_stats", payload: { active, completed, failed } }   # Every 5s
```

Channel: `instance:{instance_id}`

```
# Join for specific customer trace
{ event: "step_executed", payload: { node_id, type, result, timestamp } }
{ event: "state_changed", payload: { from, to, reason } }
```

### 3.3 Webhook Callbacks (Outgoing)

Kalcifer can notify external systems about journey events:

```
POST {callback_url}
Content-Type: application/json
X-Kalcifer-Signature: sha256=...

{
  "event_type": "customer.goal_reached",
  "journey_id": "j123",
  "instance_id": "i456",
  "customer_id": "c789",
  "node_id": "goal_1",
  "data": { ... },
  "timestamp": "2026-02-22T10:30:00Z"
}
```

---

## 4. Journey Graph Specification

### 4.1 Graph Format (stored in `journeys.graph` JSONB column)

```json
{
  "nodes": [
    {
      "id": "entry_1",
      "type": "event_entry",
      "position": { "x": 100, "y": 200 },
      "config": {
        "event_type": "signed_up",
        "filter": { "plan": "premium" }
      }
    },
    {
      "id": "email_1",
      "type": "send_email",
      "position": { "x": 300, "y": 200 },
      "config": {
        "template_id": "welcome_email",
        "provider": "sendgrid",
        "from": "hello@example.com"
      }
    },
    {
      "id": "wait_1",
      "type": "wait_for_event",
      "position": { "x": 500, "y": 200 },
      "config": {
        "event_type": "email_opened",
        "timeout": "3d",
        "timeout_branch": "timed_out"
      }
    },
    {
      "id": "email_2",
      "type": "send_email",
      "position": { "x": 700, "y": 100 },
      "config": {
        "template_id": "engaged_followup"
      }
    },
    {
      "id": "email_3",
      "type": "send_email",
      "position": { "x": 700, "y": 300 },
      "config": {
        "template_id": "reminder_email"
      }
    },
    {
      "id": "goal_1",
      "type": "goal_reached",
      "position": { "x": 900, "y": 200 },
      "config": {
        "goal_name": "activated",
        "exit_after_goal": true
      }
    }
  ],
  "edges": [
    { "id": "e1", "source": "entry_1", "target": "email_1" },
    { "id": "e2", "source": "email_1", "target": "wait_1" },
    { "id": "e3", "source": "wait_1", "target": "email_2", "branch": "event_received" },
    { "id": "e4", "source": "wait_1", "target": "email_3", "branch": "timed_out" },
    { "id": "e5", "source": "email_2", "target": "goal_1" },
    { "id": "e6", "source": "email_3", "target": "goal_1" }
  ],
  "exit_criteria": {
    "event_type": "unsubscribed"
  },
  "frequency_cap": {
    "email": { "max": 2, "window": "1d" },
    "sms": { "max": 1, "window": "1d" }
  }
}
```

### 4.2 Graph Validation Rules

```elixir
defmodule Kalcifer.Journeys.JourneyGraph do
  @doc "Validates journey graph structure"
  def validate(graph) do
    with :ok <- validate_has_entry(graph),
         :ok <- validate_no_cycles(graph),
         :ok <- validate_no_orphans(graph),
         :ok <- validate_edges_reference_valid_nodes(graph),
         :ok <- validate_branch_edges_complete(graph),
         :ok <- validate_node_configs(graph) do
      :ok
    end
  end

  # Cycle detection: topological sort (Kahn's algorithm)
  # Orphan detection: all nodes reachable from entry
  # Branch completeness: condition/split nodes have all required branch edges
  # Config validation: delegate to each node type's validate/1 callback
end
```

---

## 5. Node Specifications

### 5.1 Common Node Interface

Every node receives:
```elixir
%{
  config: map(),       # Node-specific configuration (from graph JSON)
  context: %{
    customer_id: String.t(),
    customer: map(),     # Customer profile (fetched from ProfileStore)
    tenant_id: String.t(),
    journey_id: String.t(),
    instance_id: String.t(),
    accumulated: map()   # Data from previous nodes
  }
}
```

### 5.2 WaitForEvent (Key Differentiator)

```elixir
defmodule Kalcifer.Engine.Nodes.Logic.WaitForEvent do
  @behaviour Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, context) do
    timeout_ms = parse_duration(config["timeout"])

    {:waiting, %{
      event_type: config["event_type"],
      event_filter: config["filter"],          # Optional: filter on event data
      timeout_ms: timeout_ms,
      timeout_branch: config["timeout_branch"] || "timed_out",
      event_branch: config["event_branch"] || "event_received"
    }}
  end

  @impl true
  def resume(_config, _context, {:event, event_data}) do
    {:branched, :event_received, %{trigger: :event, event: event_data}}
  end

  def resume(_config, _context, :timeout) do
    {:branched, :timed_out, %{trigger: :timeout}}
  end

  @impl true
  def validate(config) do
    errors = []
    errors = if !config["event_type"], do: ["event_type is required" | errors], else: errors
    errors = if !config["timeout"], do: ["timeout is required" | errors], else: errors

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  @impl true
  def config_schema do
    %{
      "type" => "object",
      "required" => ["event_type", "timeout"],
      "properties" => %{
        "event_type" => %{"type" => "string", "description" => "Customer event to wait for"},
        "timeout" => %{"type" => "string", "pattern" => "^\\d+[smhd]$", "description" => "Timeout duration (e.g., 3d, 12h, 30m)"},
        "filter" => %{"type" => "object", "description" => "Optional filter on event data"},
        "timeout_branch" => %{"type" => "string", "default" => "timed_out"},
        "event_branch" => %{"type" => "string", "default" => "event_received"}
      }
    }
  end
end
```

### 5.3 ABSplit

```elixir
defmodule Kalcifer.Engine.Nodes.Logic.ABSplit do
  @behaviour Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, context) do
    variants = config["variants"]
    # Deterministic hash-based assignment (same customer always gets same variant)
    hash = :erlang.phash2({context.customer_id, context.journey_id})
    total_weight = Enum.sum(Enum.map(variants, & &1["weight"]))
    point = rem(hash, total_weight)

    selected = select_variant(variants, point)
    {:branched, String.to_atom(selected["key"]), %{variant: selected["key"]}}
  end

  defp select_variant([variant | rest], point) do
    if point < variant["weight"] do
      variant
    else
      select_variant(rest, point - variant["weight"])
    end
  end

  @impl true
  def config_schema do
    %{
      "type" => "object",
      "required" => ["variants"],
      "properties" => %{
        "variants" => %{
          "type" => "array",
          "minItems" => 2,
          "maxItems" => 5,
          "items" => %{
            "type" => "object",
            "required" => ["key", "weight"],
            "properties" => %{
              "key" => %{"type" => "string"},
              "weight" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
            }
          }
        }
      }
    }
  end
end
```

---

## 6. Performance Specifications

### 6.1 Memory Budget

| Component | Per-unit Memory | Max Units | Total |
|-----------|----------------|-----------|-------|
| Idle JourneyServer | ~2-3 KB | 100,000 | ~250 MB |
| Active JourneyServer (executing node) | ~10-50 KB | 1,000 | ~50 MB |
| EventRouter ETS table | ~100 bytes/entry | 500,000 | ~50 MB |
| NodeRegistry ETS | ~1 KB/node type | 50 | ~50 KB |
| Phoenix connections (WS) | ~10 KB | 10,000 | ~100 MB |
| Ecto connection pool | ~5 MB/conn | 20 | ~100 MB |
| **Total (100K journeys)** | | | **~600 MB** |

### 6.2 Latency Targets

| Operation | p50 | p99 | p99.9 |
|-----------|-----|-----|-------|
| Event ingestion (API → EventRouter) | < 5ms | < 20ms | < 50ms |
| Logic node execution | < 2ms | < 10ms | < 50ms |
| Channel node execution (excl. provider) | < 10ms | < 50ms | < 200ms |
| State persistence (PG write) | < 5ms | < 20ms | < 100ms |
| Segment evaluation (ES query) | < 50ms | < 200ms | < 500ms |
| Analytics event → ClickHouse | < 5s | < 15s | < 30s |

### 6.3 Throughput Targets

| Metric | Target (single node) | Target (3-node cluster) |
|--------|---------------------|------------------------|
| Events ingested/sec | 10,000 | 25,000 |
| Journey instances started/sec | 1,000 | 3,000 |
| Node executions/sec | 50,000 | 150,000 |
| Channel sends/sec | 5,000 | 15,000 |
| ClickHouse batch inserts/sec | 100 (batched) | 300 |

---

## 7. Configuration

### 7.1 Environment Variables

```bash
# Database
DATABASE_URL=ecto://user:pass@localhost:5432/optio_flow
DATABASE_POOL_SIZE=20

# Elasticsearch
ELASTICSEARCH_URL=http://localhost:9200
ELASTICSEARCH_PREFIX=optioflow_          # Index prefix for multi-tenancy

# ClickHouse
CLICKHOUSE_URL=http://localhost:8123
CLICKHOUSE_DATABASE=optio_flow

# Phoenix
SECRET_KEY_BASE=...                       # Generate with mix phx.gen.secret
PHX_HOST=localhost
PHX_PORT=6000

# Security
ENCRYPTION_KEY=...                        # 32-byte AES key for Cloak.Ecto
JWT_SECRET=...                            # JWT signing key

# Clustering (optional)
CLUSTER_ENABLED=false
CLUSTER_STRATEGY=dns                      # dns | kubernetes | gossip
CLUSTER_DNS_QUERY=optioflow.local

# Feature flags
ENABLE_CUSTOM_CODE=false                  # Lua sandbox for CustomCode nodes
ENABLE_CLICKHOUSE=true                    # Disable to run without ClickHouse

# Provider defaults (per-tenant overrides in DB)
DEFAULT_EMAIL_PROVIDER=sendgrid
DEFAULT_SMS_PROVIDER=twilio

# Oban
OBAN_QUEUES=journey_triggers:10,delayed_resume:20,maintenance:5

# Broadway (Analytics pipeline)
ANALYTICS_BATCH_SIZE=1000
ANALYTICS_BATCH_TIMEOUT_MS=5000

# Rate limiting
RATE_LIMIT_EVENTS_PER_SECOND=1000         # Per tenant
RATE_LIMIT_API_PER_MINUTE=600             # Per tenant
```

### 7.2 Runtime Configuration

```elixir
# config/runtime.exs
import Config

config :optio_flow, Kalcifer.Repo,
  url: System.fetch_env!("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "20"))

config :optio_flow, Kalcifer.Engine,
  max_concurrent_instances: String.to_integer(System.get_env("MAX_INSTANCES", "100000")),
  recovery_batch_size: 1000,
  recovery_concurrency: 50

config :optio_flow, Oban,
  repo: Kalcifer.Repo,
  queues: [
    journey_triggers: 10,
    delayed_resume: 20,
    maintenance: 5
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron, crontab: [
      {"* * * * *", Kalcifer.Workers.SegmentEntryEvaluator}
    ]}
  ]
```

---

## 8. Dependencies (mix.exs)

```elixir
defp deps do
  [
    # Web
    {:phoenix, "~> 1.7"},
    {:phoenix_pubsub, "~> 2.1"},
    {:bandit, "~> 1.5"},             # HTTP server (lighter than Cowboy)
    {:corsica, "~> 2.1"},

    # Database
    {:ecto_sql, "~> 3.12"},
    {:postgrex, "~> 0.19"},

    # Job processing
    {:oban, "~> 2.18"},

    # Data pipeline
    {:broadway, "~> 1.1"},

    # HTTP client
    {:finch, "~> 0.19"},
    {:req, "~> 0.5"},               # High-level HTTP (wraps Finch)

    # Auth
    {:guardian, "~> 2.3"},
    {:argon2_elixir, "~> 4.0"},     # Password hashing

    # Encryption
    {:cloak_ecto, "~> 1.3"},

    # Serialization
    {:jason, "~> 1.4"},

    # Observability
    {:prom_ex, "~> 1.9"},
    {:opentelemetry, "~> 1.4"},
    {:opentelemetry_phoenix, "~> 1.2"},
    {:opentelemetry_ecto, "~> 1.2"},
    {:logger_json, "~> 6.0"},

    # Clustering
    {:libcluster, "~> 3.3"},
    {:horde, "~> 0.9"},             # Distributed DynamicSupervisor + Registry

    # Sandbox
    {:luerl, "~> 1.2"},             # Lua VM in Erlang (for CustomCode node)

    # AI Designer
    {:instructor, "~> 0.1"},        # Structured output from LLMs (JSON mode)
    {:xlsx_reader, "~> 0.8"},       # Excel file parsing
    {:csv, "~> 3.2"},               # CSV parsing
    {:pandex, "~> 0.2"},            # Word/PDF → text extraction

    # Utilities
    {:timex, "~> 3.7"},             # Time parsing/formatting
    {:nimble_options, "~> 1.1"},    # Config validation

    # Dev & Test
    {:credo, "~> 1.7", only: [:dev, :test]},
    {:dialyxir, "~> 1.4", only: [:dev, :test]},
    {:ex_machina, "~> 2.8", only: :test},
    {:mox, "~> 1.1", only: :test},
    {:stream_data, "~> 1.1", only: :test},     # Property-based testing
    {:benchee, "~> 1.3", only: :dev}
  ]
end
```
