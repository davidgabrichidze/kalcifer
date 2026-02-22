# Kalcifer — Architecture Document

**Version**: 1.0
**Date**: 2026-02-22
**Status**: Draft

---

## 1. Architecture Overview

Kalcifer follows a **modular monolith** architecture deployed as a single Elixir/OTP application. This is a deliberate choice: monolith for simplicity of deployment and operations, modular for separation of concerns and future extraction if needed.

```
┌──────────────────────────────────────────────────────────────────┐
│                        Kalcifer System                           │
│                                                                  │
│  ┌─────────────┐ ┌──────────────┐ ┌────────────┐ ┌───────────┐  │
│  │   Phoenix    │ │   Journey    │ │  AI        │ │ Analytics │  │
│  │   Web API    │ │   Engine     │ │  Designer  │ │ Pipeline  │  │
│  │             │ │   (OTP)      │ │  (LLM)     │ │ (Broadway)│  │
│  └──────┬──────┘ └──────┬───────┘ └─────┬──────┘ └─────┬─────┘  │
│         │               │               │               │        │
│  ┌──────┴───────────────┴───────────────┴───────────────┴─────┐  │
│  │                   Core Domain Services                      │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │  │
│  │  │ Journeys │ │ Customers│ │ Channels │ │  Versioning  │  │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │  │
│  └──────────────────────────┬─────────────────────────────────┘  │
│                              │                                   │
│  ┌───────────────────────────┴────────────────────────────────┐  │
│  │                  Infrastructure Layer                       │  │
│  │  ┌──────┐ ┌───────┐ ┌────────────┐ ┌──────┐ ┌──────────┐  │  │
│  │  │ Ecto │ │Elastic│ │ ClickHouse │ │ Oban │ │ LLM API  │  │  │
│  │  │ (PG) │ │Search │ │            │ │(Jobs)│ │(provider)│  │  │
│  │  └──────┘ └───────┘ └────────────┘ └──────┘ └──────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
         │              │              │                │
    PostgreSQL    Elasticsearch    ClickHouse    LLM Provider
                                              (OpenAI/Anthropic/
                                               self-hosted)
```

---

## 2. System Components

### 2.1 Phoenix Web API

**Responsibility**: HTTP API, WebSocket connections, authentication, rate limiting.

```
lib/optio_flow_web/
├── controllers/
│   ├── journey_controller.ex        # CRUD journeys
│   ├── execution_controller.ex      # Trigger/pause/resume
│   ├── customer_controller.ex       # Customer profile API
│   ├── event_controller.ex          # Event ingestion API
│   ├── webhook_controller.ex        # Webhook entry points
│   ├── analytics_controller.ex      # Metrics & reporting
│   └── admin_controller.ex          # System administration
├── channels/
│   ├── journey_channel.ex           # Real-time journey monitoring
│   └── execution_channel.ex         # Per-journey live updates
├── plugs/
│   ├── authenticate.ex              # API key / JWT verification
│   ├── rate_limit.ex                # Per-tenant rate limiting
│   └── tenant_context.ex            # Multi-tenancy context
└── router.ex
```

**Key Design Decisions**:
- REST API is primary interface (API-first)
- Phoenix Channels for real-time monitoring (not polling)
- Plug pipeline for cross-cutting concerns (auth, rate limiting, tenant isolation)
- No server-side rendering — frontend is a separate SPA/component

### 2.2 Journey Engine (OTP Core)

**Responsibility**: Journey execution, state management, node dispatching, event handling.

This is the heart of Kalcifer and its primary differentiator.

```
lib/optio_flow/engine/
├── journey_supervisor.ex            # DynamicSupervisor for journey instances
├── journey_server.ex                # GenServer per journey instance
├── journey_state.ex                 # State struct & transitions
├── node_registry.ex                 # Node type registry
├── node_executor.ex                 # Node dispatch & execution
├── event_router.ex                  # Customer event → journey instance routing
├── frequency_cap.ex                 # Cross-journey frequency enforcement
├── recovery.ex                      # Crash recovery from persistent state
└── nodes/
    ├── behaviour.ex                 # @behaviour NodeBehaviour
    ├── entry/
    │   ├── segment_entry.ex
    │   ├── event_entry.ex
    │   └── webhook_entry.ex
    ├── channel/
    │   ├── send_email.ex
    │   ├── send_sms.ex
    │   ├── send_push.ex
    │   ├── send_whatsapp.ex
    │   └── call_webhook.ex
    ├── logic/
    │   ├── wait.ex
    │   ├── wait_until.ex
    │   ├── wait_for_event.ex
    │   ├── condition.ex
    │   ├── ab_split.ex
    │   └── frequency_cap.ex
    ├── data/
    │   ├── update_profile.ex
    │   ├── add_tag.ex
    │   └── custom_code.ex
    └── exit/
        ├── goal_reached.ex
        └── journey_exit.ex
```

#### 2.2.1 Process Architecture

```
                  Application Supervisor
                         │
          ┌──────────────┼──────────────────┐
          │              │                  │
    JourneySupervisor  EventRouter     RecoveryManager
    (DynamicSupervisor)  (GenServer)    (GenServer)
          │
    ┌─────┼─────┬─────┐
    │     │     │     │
  JS-1  JS-2  JS-3  JS-N     ← One GenServer per active journey instance
  (customer A) (customer B) ...
```

**JourneyServer (GenServer)** — One process per active customer-in-journey:

```elixir
defmodule Kalcifer.Engine.JourneyServer do
  use GenServer, restart: :transient

  defstruct [
    :journey_id,           # Journey definition ID
    :instance_id,          # This execution instance ID
    :customer_id,          # Customer in this journey
    :current_nodes,        # Set of node IDs currently active (supports parallel branches)
    :state,                # :running | :paused | :waiting | :completed | :failed
    :context,              # Accumulated data from node executions
    :entered_at,           # Timestamp
    :tenant_id             # Multi-tenancy
  ]

  # --- Lifecycle ---

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: via_tuple(args.instance_id))
  end

  def init(args) do
    state = %__MODULE__{
      journey_id: args.journey_id,
      instance_id: args.instance_id,
      customer_id: args.customer_id,
      current_nodes: MapSet.new([args.entry_node_id]),
      state: :running,
      context: %{},
      entered_at: DateTime.utc_now(),
      tenant_id: args.tenant_id
    }

    # Subscribe to customer events for WaitForEvent nodes
    Phoenix.PubSub.subscribe(Kalcifer.PubSub, "customer:#{args.customer_id}")

    # Persist initial state
    Persistence.save_instance(state)

    # Execute first node
    {:ok, state, {:continue, :execute_current}}
  end

  # --- Node Execution ---

  def handle_continue(:execute_current, state) do
    state = execute_active_nodes(state)
    {:noreply, state}
  end

  # --- Event Handling (for WaitForEvent) ---

  def handle_info({:customer_event, event}, state) do
    state = EventRouter.route_to_waiting_nodes(state, event)
    {:noreply, state}
  end

  # --- Timer Handling (for Wait/WaitUntil) ---

  def handle_info({:timer_expired, node_id}, state) do
    state = complete_node(state, node_id, :timeout)
    {:noreply, state}
  end
end
```

**Key Property**: Each JourneyServer is **completely isolated**. A crash in one customer's journey execution:
- Is caught by DynamicSupervisor
- Does NOT affect any other customer's journey
- Can be restarted from last persisted state via RecoveryManager

#### 2.2.2 Node Behaviour

Every node implements a common behaviour:

```elixir
defmodule Kalcifer.Engine.NodeBehaviour do
  @doc "Execute the node. Returns outcome for routing."
  @callback execute(node_config :: map(), context :: map()) ::
    {:completed, result :: map()} |
    {:branched, branch_key :: atom(), result :: map()} |
    {:waiting, wait_config :: map()} |
    {:failed, reason :: term()}

  @doc "Handle resume from waiting state (for async nodes)."
  @callback resume(node_config :: map(), context :: map(), trigger :: term()) ::
    {:completed, result :: map()} |
    {:branched, branch_key :: atom(), result :: map()} |
    {:failed, reason :: term()}

  @doc "Validate node configuration at design time."
  @callback validate(node_config :: map()) ::
    :ok | {:error, [String.t()]}

  @doc "JSON Schema for the node's configuration."
  @callback config_schema() :: map()

  @optional_callbacks [resume: 3]
end
```

**Execution Outcomes**:
- `{:completed, result}` — Node done, proceed to next node(s) via edges
- `{:branched, :true_branch, result}` — Condition/split node, take specific branch
- `{:waiting, config}` — Node is async (Wait, WaitForEvent), will resume later
- `{:failed, reason}` — Node failed, trigger error handling

#### 2.2.3 Event Router

The EventRouter is a dedicated GenServer that maintains a mapping of `{customer_id, event_type} → [instance_ids]` for all active WaitForEvent nodes.

```elixir
# When a WaitForEvent node starts waiting:
EventRouter.register_wait(customer_id, event_type, instance_id, node_id)

# When a customer event arrives (via API):
EventRouter.dispatch(%{customer_id: "c123", event_type: "email_opened", data: %{...}})
# → Finds all instances waiting for this customer+event
# → Sends message to each JourneyServer
# → JourneyServer resumes the WaitForEvent node

# When wait completes or times out:
EventRouter.unregister_wait(customer_id, event_type, instance_id, node_id)
```

**Implementation**: ETS table for O(1) lookup, backed by periodic persistence to PostgreSQL.

### 2.3 AI Journey Designer

**Responsibility**: Convert natural language, conversation, and uploaded documents into valid journey graphs.

```
lib/optio_flow/ai_designer/
├── designer.ex                      # Main orchestrator — conversation → graph
├── conversation.ex                  # Multi-turn conversation state management
├── prompt_builder.ex                # System prompt + few-shot examples
├── graph_generator.ex               # LLM response → validated journey graph
├── document_parser.ex               # Excel/CSV/Word/PDF → structured intent
├── graph_differ.ex                  # Compute visual diff between two versions
├── suggestion_engine.ex             # Analytics-based optimization suggestions
└── providers/
    ├── provider.ex                  # @behaviour LLMProvider
    ├── anthropic.ex                 # Claude API (recommended)
    ├── openai.ex                    # GPT-4 API
    └── ollama.ex                    # Self-hosted LLM (Ollama/vLLM)
```

#### 2.3.1 Conversation → Graph Flow

```
User: "I want a 30-day onboarding journey. Start with a welcome email.
       Wait 3 days, check if they activated. If yes, send upsell.
       If no, send a reminder SMS, wait 2 more days, then try email again."

         │
         ▼
┌──────────────────┐
│  PromptBuilder   │  Build system prompt with:
│                  │  - Node type catalog (20 nodes, their config schemas)
│                  │  - Graph JSON format specification
│                  │  - Few-shot examples (5-10 example conversations)
│                  │  - Current customer profile schema (available fields)
│                  │  - Available channel providers
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   LLM Provider   │  Send conversation + system prompt
│  (Anthropic /    │  Receive structured JSON response
│   OpenAI /       │  Streaming for real-time preview
│   self-hosted)   │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  GraphGenerator  │  Parse LLM response → journey graph JSON
│                  │  Validate graph (DAG, no orphans, valid node configs)
│                  │  If invalid → re-prompt LLM with validation errors
│                  │  Return valid graph + natural language explanation
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  GraphDiffer     │  If modifying existing journey:
│                  │  Compute diff (added/removed/changed nodes)
│                  │  Present visual diff to user for approval
└──────────────────┘
```

#### 2.3.2 Document Upload Flow

```
User uploads: "Q1_Onboarding_Campaign.xlsx"

         │
         ▼
┌──────────────────┐
│ DocumentParser   │  Detect format (Excel/CSV/Word/PDF)
│                  │  Extract structured data:
│                  │  - Steps/stages (from rows or sections)
│                  │  - Timing (from columns or text)
│                  │  - Channels (from mentions of email/SMS/push)
│                  │  - Conditions (from if/then language)
│                  │  - Segments (from audience descriptions)
│                  │  Output: structured intent document
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  PromptBuilder   │  Inject structured intent into prompt:
│                  │  "User uploaded a campaign document. Here is the
│                  │   parsed content: {steps, timing, channels...}
│                  │   Generate a journey graph that implements this."
└────────┬─────────┘
         │
         ▼
   (same LLM → GraphGenerator → validation flow as above)
```

#### 2.3.3 LLM Provider Abstraction

```elixir
defmodule Kalcifer.AiDesigner.LLMProvider do
  @callback chat(messages :: [map()], opts :: keyword()) ::
    {:ok, String.t()} | {:error, term()}

  @callback stream(messages :: [map()], opts :: keyword()) ::
    {:ok, Stream.t()} | {:error, term()}
end

# Users configure their preferred provider:
# config :optio_flow, :llm_provider, Kalcifer.AiDesigner.Providers.Anthropic
# config :optio_flow, :llm_api_key, System.get_env("ANTHROPIC_API_KEY")
#
# Self-hosted option (no external API calls):
# config :optio_flow, :llm_provider, Kalcifer.AiDesigner.Providers.Ollama
# config :optio_flow, :llm_base_url, "http://localhost:11434"
```

### 2.4 Journey Versioning & Live Migration

**Responsibility**: Manage immutable journey versions and migrate active instances between versions.

```
lib/optio_flow/versioning/
├── version_manager.ex               # Create/publish/rollback versions
├── version_differ.ex                # Compute structural diff between versions
├── node_mapper.ex                   # Auto-detect + manual node mapping between versions
├── migration_planner.ex             # Plan migration (strategy, batching, rollout %)
├── migration_executor.ex            # Execute migration on active instances
├── migration_monitor.ex             # Track migration progress, detect failures
└── ai_mapper.ex                     # AI-assisted node mapping for complex changes
```

#### 2.4.1 Version Model

```
Journey (mutable metadata: name, status)
  │
  ├── Version 1 (immutable graph snapshot)
  │     ├── graph: { nodes: [...], edges: [...] }
  │     ├── published_at: timestamp
  │     ├── published_by: user_id
  │     └── changelog: "Initial version"
  │
  ├── Version 2 (immutable graph snapshot)
  │     ├── graph: { nodes: [...], edges: [...] }
  │     ├── published_at: timestamp
  │     ├── node_mapping: { v1_node_id → v2_node_id, ... }
  │     ├── migration_strategy: :migrate_all | :new_entries_only | :gradual
  │     ├── migration_config: { rollout_percent: 10, batch_size: 1000 }
  │     └── changelog: "Added SMS fallback after email"
  │
  └── Version 3 (draft — mutable until published)
        └── graph: { nodes: [...], edges: [...] }
```

#### 2.4.2 Node Mapping

When publishing a new version, Kalcifer must determine how nodes in the old version correspond to nodes in the new version:

```
Version 1:                    Version 2:
┌───────┐                    ┌───────┐
│Entry  │ ──────────────────→│Entry  │  (same node, auto-mapped)
└───┬───┘                    └───┬───┘
    │                            │
┌───▼───┐                    ┌──▼────┐
│Email 1│ ──────────────────→│Email 1│  (same node, config changed)
└───┬───┘                    └───┬───┘
    │                            │
┌───▼───┐                    ┌──▼────┐
│Wait 3d│ ──────────────────→│Wait 5d│  (mapped: same position, duration changed)
└───┬───┘                    └───┬───┘
    │                            │
    │                        ┌──▼────┐
    │              (NEW) ←── │SMS    │  (new node — inserted)
    │                        └───┬───┘
    │                            │
┌───▼───┐                    ┌──▼────┐
│Goal   │ ──────────────────→│Goal   │  (same node, auto-mapped)
└───────┘                    └───────┘
```

**Auto-mapping rules** (NodeMapper):
1. Nodes with same `id` → automatically mapped
2. Nodes with same `type` + similar `config` → suggested mapping
3. Unmatched nodes → AI suggests mapping or marks as added/removed
4. Manual override always available

#### 2.4.3 Migration Execution

```
Migration Strategy: "migrate_all" with batch_size: 1000

Step 1: Identify all running instances on Version 1
        SELECT * FROM journey_instances WHERE journey_id = ? AND version = 1 AND status IN ('running', 'waiting')

Step 2: For each batch of 1000 instances:
        For each instance:
          a. Find current_node in Version 1
          b. Look up node_mapping[current_node] → mapped_node in Version 2
          c. If mapped_node exists:
             → Update instance.version = 2
             → Update instance.current_nodes = [mapped_node]
             → Update instance.graph_snapshot = version_2.graph
             → If node was WaitForEvent: re-register with EventRouter
             → If node was Wait: recalculate timer if duration changed
             → Send :version_migrated message to JourneyServer process
          d. If mapped_node does NOT exist (node was removed):
             → Apply removal policy (skip_to_next | exit | hold)
          e. Persist migration event to execution_steps (audit trail)

Step 3: Monitor migration progress
        Track: migrated_count, failed_count, skipped_count
        Publish real-time progress to Phoenix Channel

Step 4: If migration_strategy is :gradual:
        → Migrate rollout_percent% of instances
        → Wait for monitoring_window (e.g., 1 hour)
        → If no anomalies detected: proceed to next batch
        → If anomalies: pause migration, alert operator
```

#### 2.4.4 Version Migration in JourneyServer

```elixir
# In JourneyServer (GenServer):

def handle_cast({:migrate_version, %{new_version: v2, node_mapping: mapping}}, state) do
  old_node = hd(MapSet.to_list(state.current_nodes))
  mapped_node = Map.get(mapping, old_node)

  case mapped_node do
    nil ->
      # Node was removed — apply removal policy
      handle_removed_node(state, old_node, v2)

    new_node_id ->
      # Node exists in new version — migrate
      new_state = %{state |
        version: v2.version_number,
        graph: v2.graph,
        current_nodes: MapSet.new([new_node_id])
      }

      # Re-register timers/event waits if needed
      new_state = reregister_async_state(new_state, old_node, new_node_id, v2)

      # Persist migration
      Persistence.save_migration_event(state.instance_id, state.version, v2.version_number)
      Persistence.save_instance(new_state)

      # Continue execution if at a synchronous node
      {:noreply, new_state, {:continue, :check_execution}}
  end
end
```

### 2.5 Analytics Pipeline (Broadway)

**Responsibility**: Process journey execution events into analytics aggregations.

```
lib/optio_flow/analytics/
├── event_producer.ex                # Broadway producer from PG notifications
├── event_processor.ex               # Transform events for ClickHouse
├── clickhouse_writer.ex             # Batch writer to ClickHouse
└── aggregation_queries.ex           # Pre-built analytical queries
```

**Flow**:
```
JourneyServer executes node
    → Persists execution event to PostgreSQL (synchronous, guaranteed)
    → PG NOTIFY on `journey_events` channel
    → Broadway producer picks up notification
    → Batch processes events
    → Writes to ClickHouse (async, eventually consistent)
    → ClickHouse materialized views compute aggregations
```

**Why Broadway (not GenStage directly)**:
- Built-in batching (ClickHouse prefers batch inserts)
- Built-in rate limiting
- Built-in graceful shutdown
- Backpressure to PostgreSQL NOTIFY

---

## 3. Data Architecture

### 3.1 PostgreSQL — Source of Truth

PostgreSQL stores all operational data. Ecto with migrations.

```
┌─────────────────────────────────────────────────────────────┐
│                      PostgreSQL Schema                       │
│                                                             │
│  ┌──────────────┐    ┌──────────────────┐                   │
│  │   tenants    │───<│    journeys      │                   │
│  │              │    │                  │                   │
│  │ id           │    │ id               │                   │
│  │ name         │    │ tenant_id (FK)   │                   │
│  │ api_key_hash │    │ name             │                   │
│  │ settings     │    │ status (enum)    │                   │
│  └──────────────┘    │ active_version   │  ← current ver #  │
│                      │ entry_config     │                   │
│                      │ exit_criteria    │                   │
│                      │ frequency_cap    │                   │
│                      │ inserted_at      │                   │
│                      │ updated_at       │                   │
│                      └──┬──────────┬────┘                   │
│                         │          │                        │
│               ┌─────────▼───────┐  │                        │
│               │journey_versions │  │                        │
│               │                 │  │                        │
│               │ id              │  │                        │
│               │ journey_id (FK) │  │                        │
│               │ version_number  │  │  ← sequential          │
│               │ graph (jsonb)   │  │  ← immutable snapshot  │
│               │ status (enum)   │  │  ← draft/published/    │
│               │                 │  │    deprecated/rolledback│
│               │ node_mapping    │  │  ← jsonb {old→new}     │
│               │ migration_strategy│ │                        │
│               │ migration_config│  │  ← jsonb               │
│               │ changelog       │  │                        │
│               │ published_by    │  │                        │
│               │ published_at    │  │                        │
│               │ inserted_at     │  │                        │
│               └─────────────────┘  │                        │
│                                    │                        │
│               ┌────────────────────▼────┐                   │
│               │   journey_instances     │                   │
│               │                         │                   │
│               │ id                      │                   │
│               │ journey_id (FK)         │                   │
│               │ version_number          │  ← pinned version │
│               │ customer_id             │                   │
│               │ tenant_id (FK)          │                   │
│               │ status (enum)           │                   │
│               │ current_nodes           │  ← jsonb array    │
│               │ context (jsonb)         │  ← accumulated    │
│               │ entered_at              │                   │
│               │ completed_at            │                   │
│               │ exited_at               │                   │
│               │ exit_reason             │                   │
│               │ migrated_from_version   │  ← nullable       │
│               │ migrated_at             │  ← nullable       │
│               └───────────┬─────────────┘                   │
│                           │                                 │
│               ┌───────────▼─────────────┐                   │
│               │   execution_steps       │                   │
│               │                         │                   │
│               │ id                      │                   │
│               │ instance_id (FK)        │                   │
│               │ node_id                 │                   │
│               │ node_type               │                   │
│               │ version_number          │  ← version at exec│
│               │ status (enum)           │                   │
│               │ input (jsonb)           │                   │
│               │ output (jsonb)          │                   │
│               │ error (jsonb)           │                   │
│               │ started_at              │                   │
│               │ completed_at            │                   │
│               └─────────────────────────┘                   │
│                                                             │
│  ┌──────────────────────┐                                   │
│  │  journey_migrations  │  ← migration execution log        │
│  │                      │                                   │
│  │ id                   │                                   │
│  │ journey_id (FK)      │                                   │
│  │ from_version         │                                   │
│  │ to_version           │                                   │
│  │ strategy             │                                   │
│  │ status (enum)        │  ← pending/running/completed/     │
│  │                      │    failed/paused/rolled_back       │
│  │ total_instances      │                                   │
│  │ migrated_count       │                                   │
│  │ failed_count         │                                   │
│  │ skipped_count        │                                   │
│  │ started_at           │                                   │
│  │ completed_at         │                                   │
│  └──────────────────────┘                                   │
│                                                             │
│  ┌──────────────────────┐                                   │
│  │  ai_conversations    │  ← AI designer conversation log   │
│  │                      │                                   │
│  │ id                   │                                   │
│  │ tenant_id (FK)       │                                   │
│  │ journey_id (FK)      │  ← nullable (new journey)         │
│  │ messages (jsonb[])   │  ← conversation history           │
│  │ generated_graphs     │  ← jsonb[] (each AI response)     │
│  │ inserted_at          │                                   │
│  │ updated_at           │                                   │
│  └──────────────────────┘                                   │
│                                                             │
│  ┌──────────────────┐  ┌────────────────────┐               │
│  │ channel_configs  │  │ provider_credentials│              │
│  │                  │  │                    │               │
│  │ id               │  │ id                 │               │
│  │ tenant_id (FK)   │  │ tenant_id (FK)     │               │
│  │ channel_type     │  │ provider_type      │               │
│  │ provider_type    │  │ credentials (enc)  │  ← encrypted  │
│  │ config (jsonb)   │  │ inserted_at        │               │
│  └──────────────────┘  └────────────────────┘               │
│                                                             │
│  ┌──────────────────┐  ┌────────────────────┐               │
│  │  frequency_log   │  │    audit_log       │               │
│  │                  │  │                    │               │
│  │ id               │  │ id                 │               │
│  │ tenant_id        │  │ tenant_id          │               │
│  │ customer_id      │  │ actor_id           │               │
│  │ channel          │  │ action             │               │
│  │ sent_at          │  │ resource_type      │               │
│  │ journey_id       │  │ resource_id        │               │
│  │                  │  │ changes (jsonb)    │               │
│  │ INDEX: (tenant,  │  │ inserted_at        │               │
│  │  customer, chan,  │  │                    │               │
│  │  sent_at)        │  │                    │               │
│  └──────────────────┘  └────────────────────┘               │
│                                                             │
│  ┌──────────────────┐                                       │
│  │   oban_jobs      │  ← Oban's table for scheduled jobs    │
│  │                  │    (Wait, WaitUntil, cron triggers)    │
│  └──────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

**Key Indexes**:
```sql
-- Journey instances: lookup by customer in journey
CREATE INDEX idx_instances_journey_customer ON journey_instances(journey_id, customer_id) WHERE status = 'running';

-- Journey instances: recovery after restart
CREATE INDEX idx_instances_running ON journey_instances(status) WHERE status IN ('running', 'waiting');

-- Journey instances: per-version count (for migration progress)
CREATE INDEX idx_instances_version ON journey_instances(journey_id, version_number) WHERE status IN ('running', 'waiting');

-- Journey versions: lookup by journey
CREATE INDEX idx_versions_journey ON journey_versions(journey_id, version_number);

-- Frequency cap: check recent sends
CREATE INDEX idx_frequency_log ON frequency_log(tenant_id, customer_id, channel, sent_at DESC);

-- Execution steps: trace customer journey (including version)
CREATE INDEX idx_steps_instance ON execution_steps(instance_id, started_at);

-- Migrations: active migrations
CREATE INDEX idx_migrations_active ON journey_migrations(journey_id) WHERE status IN ('pending', 'running');
```

### 3.2 Elasticsearch — Customer Profiles & Segments

Elasticsearch stores customer profiles for segment evaluation. Kalcifer does NOT own this data — it integrates with external profile stores via a pluggable adapter. Elasticsearch is the default adapter.

```
# Customer profile index (managed by external system or Kalcifer sync)
PUT /customers
{
  "mappings": {
    "properties": {
      "id":           { "type": "keyword" },
      "tenant_id":    { "type": "keyword" },
      "email":        { "type": "keyword" },
      "name":         { "type": "text" },
      "attributes":   { "type": "object", "dynamic": true },
      "tags":         { "type": "keyword" },
      "segments":     { "type": "keyword" },
      "last_active":  { "type": "date" },
      "created_at":   { "type": "date" }
    }
  }
}
```

**Segment Evaluation**: When a SegmentEntry or Condition node needs to evaluate a segment, it builds an Elasticsearch query from the segment definition:

```elixir
defmodule Kalcifer.Segments.Evaluator do
  def customer_matches?(customer_id, segment_definition) do
    query = SegmentQueryBuilder.build(segment_definition)
    Elasticsearch.exists?(index: "customers", id: customer_id, query: query)
  end

  def get_matching_customers(segment_definition, opts \\ []) do
    query = SegmentQueryBuilder.build(segment_definition)
    Elasticsearch.scroll(index: "customers", query: query, opts)
  end
end
```

### 3.3 ClickHouse — Execution Analytics

ClickHouse stores high-volume execution events for analytics dashboards.

```sql
-- Raw execution events (append-only)
CREATE TABLE execution_events (
    tenant_id       LowCardinality(String),
    journey_id      String,
    instance_id     String,
    customer_id     String,
    node_id         String,
    node_type       LowCardinality(String),
    event_type      LowCardinality(String),  -- 'entered', 'completed', 'failed', 'skipped'
    branch_key      Nullable(String),
    duration_ms     UInt32,
    timestamp       DateTime64(3),
    date            Date MATERIALIZED toDate(timestamp)
) ENGINE = MergeTree()
PARTITION BY (tenant_id, toYYYYMM(timestamp))
ORDER BY (tenant_id, journey_id, timestamp, instance_id);

-- Channel delivery events (append-only)
CREATE TABLE channel_events (
    tenant_id       LowCardinality(String),
    journey_id      String,
    instance_id     String,
    customer_id     String,
    node_id         String,
    channel         LowCardinality(String),  -- 'email', 'sms', 'push', 'whatsapp'
    provider        LowCardinality(String),  -- 'sendgrid', 'twilio', etc.
    event_type      LowCardinality(String),  -- 'sent', 'delivered', 'opened', 'clicked', 'bounced', 'failed'
    metadata        String,                  -- JSON
    timestamp       DateTime64(3),
    date            Date MATERIALIZED toDate(timestamp)
) ENGINE = MergeTree()
PARTITION BY (tenant_id, toYYYYMM(timestamp))
ORDER BY (tenant_id, journey_id, timestamp);

-- Materialized view: per-node aggregation (auto-updated on insert)
CREATE MATERIALIZED VIEW node_metrics_mv
ENGINE = AggregatingMergeTree()
ORDER BY (tenant_id, journey_id, node_id, date)
AS SELECT
    tenant_id,
    journey_id,
    node_id,
    date,
    countState() AS total_entered,
    countIfState(event_type = 'completed') AS total_completed,
    countIfState(event_type = 'failed') AS total_failed,
    avgIfState(duration_ms, event_type = 'completed') AS avg_duration_ms
FROM execution_events
GROUP BY tenant_id, journey_id, node_id, date;

-- Materialized view: journey-level funnel
CREATE MATERIALIZED VIEW journey_funnel_mv
ENGINE = AggregatingMergeTree()
ORDER BY (tenant_id, journey_id, date)
AS SELECT
    tenant_id,
    journey_id,
    date,
    uniqState(customer_id) AS unique_customers,
    countIfState(event_type = 'entered' AND node_type = 'goal_reached') AS conversions,
    countIfState(event_type = 'completed' AND node_type = 'journey_exit') AS exits
FROM execution_events
GROUP BY tenant_id, journey_id, date;

-- Materialized view: channel performance
CREATE MATERIALIZED VIEW channel_metrics_mv
ENGINE = AggregatingMergeTree()
ORDER BY (tenant_id, channel, provider, date)
AS SELECT
    tenant_id,
    channel,
    provider,
    date,
    countState() AS total_events,
    countIfState(event_type = 'sent') AS sent,
    countIfState(event_type = 'delivered') AS delivered,
    countIfState(event_type = 'opened') AS opened,
    countIfState(event_type = 'clicked') AS clicked,
    countIfState(event_type = 'bounced') AS bounced,
    countIfState(event_type = 'failed') AS failed
FROM channel_events
GROUP BY tenant_id, channel, provider, date;
```

---

## 4. OTP Supervision Tree

```
Kalcifer.Application
├── Kalcifer.Repo (Ecto PostgreSQL)
├── Kalcifer.Elasticsearch.Pool (Finch HTTP pool)
├── Kalcifer.ClickHouse.Pool (Finch HTTP pool)
├── KalciferWeb.Endpoint (Phoenix HTTP/WS)
├── Kalcifer.PubSub (Phoenix.PubSub — pg adapter for clustering)
│
├── Kalcifer.Engine.Supervisor (rest_for_one)
│   ├── Kalcifer.Engine.NodeRegistry (GenServer — ETS-backed node type catalog)
│   ├── Kalcifer.Engine.EventRouter (GenServer — customer event → instance routing)
│   ├── Kalcifer.Engine.FrequencyCapServer (GenServer — ETS-backed frequency tracking)
│   ├── Kalcifer.Engine.JourneySupervisor (DynamicSupervisor)
│   │   ├── JourneyServer-{instance-1} (GenServer)
│   │   ├── JourneyServer-{instance-2} (GenServer)
│   │   └── ... (up to 100K+ per node)
│   └── Kalcifer.Engine.RecoveryManager (GenServer — startup recovery)
│
├── Kalcifer.Scheduler.Supervisor (one_for_one)
│   └── Oban (PostgreSQL-backed job processing)
│       ├── Oban.Queue.JourneyTriggers (cron/scheduled entry evaluation)
│       ├── Oban.Queue.DelayedResume (Wait/WaitUntil node timeouts)
│       └── Oban.Queue.Maintenance (cleanup, archival)
│
├── Kalcifer.Analytics.Supervisor (one_for_one)
│   └── Kalcifer.Analytics.Pipeline (Broadway)
│       ├── Producer (PG LISTEN on journey_events)
│       ├── Processors (configurable concurrency)
│       └── Batcher → ClickHouse bulk insert
│
└── Kalcifer.Integrations.Supervisor (one_for_one)
    ├── Kalcifer.Integrations.EmailPool (Finch pool for email providers)
    ├── Kalcifer.Integrations.SmsPool (Finch pool for SMS providers)
    └── Kalcifer.Integrations.WebhookPool (Finch pool for outgoing webhooks)
```

**Supervision Strategies**:
- `Engine.Supervisor`: `rest_for_one` — if EventRouter crashes, JourneySupervisor restarts (instances re-register)
- `JourneySupervisor`: `DynamicSupervisor` with `:transient` restart — only restart on abnormal exit
- `Analytics.Supervisor`: `one_for_one` — analytics failure doesn't affect engine
- `Integrations.Supervisor`: `one_for_one` — one provider pool crash doesn't affect others

---

## 5. Data Flow Patterns

### 5.1 Customer Enters Journey (Event-triggered)

```
1. External system POST /api/v1/events
   { customer_id: "c123", event_type: "signed_up", data: {...} }

2. Phoenix controller validates & authenticates (API key → tenant)

3. EventController dispatches to EventRouter:
   EventRouter.dispatch(tenant_id, customer_id, event)

4. EventRouter checks:
   a. Active WaitForEvent nodes waiting for this customer+event?
      → Send message to each JourneyServer
   b. Journey entry triggers matching this event type?
      → For each matching journey: start new JourneyServer

5. JourneyServer starts:
   a. DynamicSupervisor.start_child(JourneySupervisor, {JourneyServer, args})
   b. JourneyServer.init:
      - Persist journey_instance to PostgreSQL
      - PG NOTIFY 'journey_events' (for analytics pipeline)
      - Execute entry node
      - Discover next nodes from edges
      - Execute next nodes (continue until async node or completion)

6. Analytics Pipeline (async):
   - Broadway producer receives PG notification
   - Batches events
   - Writes to ClickHouse
```

### 5.2 WaitForEvent Flow

```
1. JourneyServer reaches WaitForEvent node:
   WaitForEvent.execute(%{event: "email_opened", timeout: 3_days})
   → Returns {:waiting, %{event: "email_opened", timeout: 259_200_000}}

2. JourneyServer:
   a. Registers with EventRouter: {customer_id, "email_opened"} → instance_id
   b. Schedules timeout via Oban: %{instance_id: id, node_id: nid} | schedule_in: 259_200
   c. Persists state to PostgreSQL (status: :waiting, current_nodes: [wait_node_id])
   d. JourneyServer stays alive but idle (minimal memory — just a GenServer with state)

3a. Customer opens email (event arrives first):
    EventRouter.dispatch → JourneyServer receives {:customer_event, event}
    → Cancel Oban timeout job
    → WaitForEvent.resume(config, context, {:event, event_data})
    → Returns {:branched, :event_received, result}
    → JourneyServer follows "event_received" edge

3b. Timeout fires first:
    Oban executes job → sends message to JourneyServer
    → JourneyServer receives {:timer_expired, node_id}
    → Unregister from EventRouter
    → WaitForEvent.resume(config, context, :timeout)
    → Returns {:branched, :timed_out, result}
    → JourneyServer follows "timed_out" edge
```

### 5.3 Crash Recovery Flow

```
1. System restarts (deploy, crash, hardware failure)

2. Application starts → Supervision tree initializes

3. RecoveryManager starts:
   a. Query PostgreSQL: SELECT * FROM journey_instances WHERE status IN ('running', 'waiting')
   b. For each instance:
      - Start JourneyServer with persisted state
      - Re-register WaitForEvent subscriptions with EventRouter
      - Re-check Oban jobs (Oban handles its own recovery)
      - Resume execution from last persisted node

4. Recovery is idempotent:
   - Node execution is designed for at-least-once semantics
   - Channel nodes check for deduplication before sending
   - State transitions are persisted BEFORE side effects
```

---

## 6. Integration Architecture

### 6.1 Channel Provider Abstraction

```elixir
defmodule Kalcifer.Channels.EmailProvider do
  @callback send(to :: String.t(), subject :: String.t(), body :: String.t(), opts :: map()) ::
    {:ok, provider_message_id :: String.t()} | {:error, reason :: term()}

  @callback parse_webhook(payload :: map()) ::
    {:ok, [%{event_type: atom(), message_id: String.t(), data: map()}]} | {:error, term()}
end

# Implementations:
defmodule Kalcifer.Channels.Email.SendGrid do
  @behaviour Kalcifer.Channels.EmailProvider
  # ...
end

defmodule Kalcifer.Channels.Email.SES do
  @behaviour Kalcifer.Channels.EmailProvider
  # ...
end

defmodule Kalcifer.Channels.Email.SMTP do
  @behaviour Kalcifer.Channels.EmailProvider
  # ...
end
```

### 6.2 Customer Profile Adapter

```elixir
defmodule Kalcifer.Customers.ProfileStore do
  @callback get_profile(tenant_id :: String.t(), customer_id :: String.t()) ::
    {:ok, map()} | {:error, :not_found}

  @callback update_profile(tenant_id :: String.t(), customer_id :: String.t(), changes :: map()) ::
    :ok | {:error, term()}

  @callback evaluate_segment(tenant_id :: String.t(), segment :: map(), customer_id :: String.t()) ::
    boolean()

  @callback query_segment(tenant_id :: String.t(), segment :: map(), opts :: keyword()) ::
    {:ok, Stream.t()} | {:error, term()}
end

# Default: Elasticsearch
defmodule Kalcifer.Customers.ElasticsearchStore do
  @behaviour Kalcifer.Customers.ProfileStore
  # ...
end

# Alternative: PostgreSQL (for smaller datasets)
defmodule Kalcifer.Customers.PostgresStore do
  @behaviour Kalcifer.Customers.ProfileStore
  # ...
end

# Alternative: External API (for embedding in other products)
defmodule Kalcifer.Customers.ExternalApiStore do
  @behaviour Kalcifer.Customers.ProfileStore
  # ...
end
```

### 6.3 Plugin SDK (Custom Nodes)

```elixir
# Third-party developers implement this behaviour
defmodule Kalcifer.Engine.NodeBehaviour do
  @callback execute(config :: map(), context :: map()) ::
    {:completed, map()} |
    {:branched, atom(), map()} |
    {:waiting, map()} |
    {:failed, term()}

  @callback validate(config :: map()) :: :ok | {:error, [String.t()]}
  @callback config_schema() :: map()   # JSON Schema
  @callback ui_schema() :: map()       # Visual editor hints (icon, color, category)
end

# Registration at startup:
# config/runtime.exs
config :optio_flow, :custom_nodes, [
  MyApp.Nodes.SlackNotify,
  MyApp.Nodes.SegmentIdentify,
  MyApp.Nodes.CustomScoring
]
```

---

## 7. Clustering & Horizontal Scaling

### 7.1 Single Node (Default)

Most deployments run on a single node. A single BEAM node can handle:
- 100K+ concurrent journey instances
- 10K+ events/second
- This covers the majority of use cases

### 7.2 Multi-Node Cluster

For larger deployments, distributed Erlang clustering:

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Node 1     │    │   Node 2     │    │   Node 3     │
│              │    │              │    │              │
│ Phoenix API  │    │ Phoenix API  │    │ Phoenix API  │
│ JourneyServers│   │ JourneyServers│   │ JourneyServers│
│ EventRouter  │    │ EventRouter  │    │ EventRouter  │
│ (local)      │    │ (local)      │    │ (local)      │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
                    Distributed Erlang
                    (EPMD / libcluster)
                           │
              ┌────────────┼────────────┐
              │            │            │
         PostgreSQL   Elasticsearch  ClickHouse
```

**Distribution Strategy**:
- **Phoenix PubSub**: pg adapter (distributed Erlang) — events broadcast to all nodes
- **JourneyServer placement**: Consistent hashing on customer_id — each customer's journeys run on one node
- **EventRouter**: Local per node + PubSub broadcast for cross-node event routing
- **Oban**: Built-in distributed job processing (PostgreSQL as coordination layer)
- **libcluster**: Automatic node discovery (Kubernetes DNS, EC2 tags, etc.)

---

## 8. Security Architecture

### 8.1 Authentication

```
API Request → Plug.Authenticate
              │
              ├── API Key (X-API-Key header)
              │   → Hash & lookup in `tenants` table
              │   → Set tenant context in conn.assigns
              │
              └── JWT Bearer Token (Authorization header)
                  → Verify signature (tenant-specific secret)
                  → Extract claims (user_id, roles, tenant_id)
                  → Set user & tenant context
```

### 8.2 Multi-tenancy Isolation

```elixir
# Every Ecto query is scoped to tenant
defmodule Kalcifer.Repo do
  def scoped(queryable) do
    tenant_id = Kalcifer.TenantContext.current_tenant_id()
    from(q in queryable, where: q.tenant_id == ^tenant_id)
  end
end

# Every JourneyServer verifies tenant on every operation
# Every Elasticsearch query includes tenant_id filter
# Every ClickHouse query includes tenant_id in WHERE
```

### 8.3 Secrets Management

- Provider credentials encrypted at rest (AES-256-GCM)
- Encryption key from environment variable (not in database)
- Credentials never logged, never in error messages
- Cloak.Ecto for transparent Ecto field encryption

---

## 9. Observability Stack

```
Kalcifer Application
    │
    ├── :telemetry events (Erlang standard)
    │   ├── phoenix.endpoint.*
    │   ├── ecto.repo.*
    │   ├── oban.job.*
    │   ├── optio_flow.engine.*        ← custom
    │   │   ├── node.execute.start/stop
    │   │   ├── journey.start/complete/fail
    │   │   └── event.dispatch
    │   └── optio_flow.channel.*       ← custom
    │       └── send.start/stop/error
    │
    ├── OpenTelemetry (traces)
    │   └── opentelemetry_phoenix + custom spans
    │       → Jaeger / Tempo / Datadog
    │
    ├── PromEx (Prometheus metrics)
    │   └── /metrics endpoint
    │       → Prometheus → Grafana
    │
    └── Logger (structured JSON)
        └── stdout → container log collector
            → Loki / ELK / CloudWatch
```

---

## 10. Architecture Decision Records

### ADR-001: Modular Monolith over Microservices

**Decision**: Single Elixir application, not separate services.
**Rationale**: OTP provides process isolation within a single VM that is equivalent to microservice isolation but without network overhead, serialization cost, or operational complexity. A modular monolith with clear boundaries can be extracted later if needed.

### ADR-002: PostgreSQL as Primary, not Elasticsearch

**Decision**: PostgreSQL for all operational data. Elasticsearch only for customer profile queries/segments.
**Rationale**: ACID transactions for journey state, Ecto migrations for schema evolution, foreign keys for data integrity. Elasticsearch excels at search and segment evaluation but is not designed for stateful CRUD operations.

### ADR-003: Oban over Custom Scheduler

**Decision**: Use Oban for all scheduled work (delayed tasks, cron triggers, maintenance).
**Rationale**: PostgreSQL-backed, distributed, observable, battle-tested. Custom Redis scheduler adds infrastructure dependency and implementation burden with no material advantage.

### ADR-004: Broadway for Analytics Pipeline

**Decision**: Broadway for PG → ClickHouse event pipeline.
**Rationale**: Built-in batching (ClickHouse performs best with batch inserts), backpressure, rate limiting, and graceful shutdown. Lighter than Kafka for this use case.

### ADR-005: Process-per-Journey-Instance

**Decision**: Each active journey instance is a dedicated GenServer process.
**Rationale**: Complete isolation (one crash doesn't affect others), natural concurrency model, built-in state management, efficient memory usage (~2KB per idle process), BEAM scheduler handles fairness.

### ADR-006: Apache 2.0 License

**Decision**: Permissive open-source license.
**Rationale**: Maximum adoption. Allows embedding in commercial products without restriction. Monetization via managed cloud offering and enterprise features, not license restrictions.

### ADR-007: AI-first Journey Design over Visual-first

**Decision**: AI conversational interface is the primary journey creation method. Visual editor is for refinement.
**Rationale**: Visual drag-and-drop is the industry default but is universally disliked for complex journeys. Marketing teams think in strategy documents and verbal descriptions, not node graphs. AI translates natural intent into executable graphs, then the visual editor allows fine-tuning. This inverts the traditional flow and removes the biggest friction point in journey creation.

### ADR-008: Pluggable LLM Provider

**Decision**: LLM provider is a behaviour (`@behaviour LLMProvider`) with Anthropic, OpenAI, and Ollama adapters.
**Rationale**: Self-hosted deployments may require fully offline operation (no external API calls). Ollama/vLLM adapter enables AI features without cloud dependency. Enterprise customers can use their existing AI provider agreements. Provider abstraction also insulates from API changes.

### ADR-009: Immutable Versions with Live Migration

**Decision**: Journey versions are immutable snapshots. Active instances can migrate between versions via configurable strategies.
**Rationale**: The alternative (mutable journeys with "save and pray") is what every competitor does, and it's broken. A 6-month journey with 50K active customers cannot be safely modified without understanding where each customer is and how changes affect them. Immutable versions + explicit node mapping + migration strategies make this safe, auditable, and reversible. This is Kalcifer's strongest operational differentiator.

### ADR-010: AI-assisted Node Mapping

**Decision**: When publishing a new version, AI suggests node mappings between versions based on structural similarity and semantic understanding.
**Rationale**: Manual node mapping is tedious for complex changes. Auto-mapping by node ID handles trivial cases. AI fills the gap for non-trivial changes (node renamed, split into two, merged, reordered) by understanding the semantic intent of the change.
