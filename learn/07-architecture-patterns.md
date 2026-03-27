# Architecture Patterns — How Kalcifer Ties It All Together

## Context: This Is Not a CRUD App

Kalcifer is a flow orchestration engine. A single customer journey can span hours, days, or weeks — waiting for events, branching on conditions, sending messages across channels, invoking AI decisions. The architecture must handle: thousands of concurrent long-running flows, crash recovery without data loss, dynamic extension (new node types at runtime), multi-tenant isolation, and reliable delivery across unreliable channels.

This guide explains the architectural patterns that make this possible and WHY each pattern was chosen.

## Pattern 1: Process-Per-Instance

### What It Is
Every active FlowInstance gets its own GenServer process (FlowServer). If 5,000 customers are in flows, there are 5,000 FlowServer processes.

### Why This Pattern

**Alternative A: Single process handles all instances** — becomes a bottleneck. One slow node execution blocks all other instances. One crash kills everything.

**Alternative B: Stateless workers (like HTTP request handlers)** — can't maintain execution context across wait/resume cycles efficiently. Would need to reload all state from DB for every step.

**Chosen approach: Process per instance** gives you:
- **Isolation**: One instance crashes, others are unaffected
- **Concurrency**: All instances execute simultaneously (BEAM scheduler)
- **State locality**: Instance state lives in process memory, fast access
- **Natural lifecycle**: Process start = flow start, process end = flow completion

### How It Works

```
API: POST /api/v1/trigger/:flow_id
  → TriggerController
  → Engine.trigger_flow(tenant_id, flow_id, customer_id, context)
    → Create FlowInstance record (DB)
    → DynamicSupervisor.start_child(FlowSupervisor, {FlowServer, opts})
      → FlowServer.init/1 loads graph, begins execution
        → Execute node 1 → node 2 → ... → wait node
          → Persist state to DB
          → Schedule Oban ResumeFlowJob
          → Process terminates (or stays alive if configured)
```

### Memory Efficiency
When a flow hits a wait node (e.g., "wait 3 days"), the GenServer can terminate. State is persisted to PostgreSQL. After 3 days, Oban fires ResumeFlowJob, which starts a NEW FlowServer that loads state from DB and continues. This means idle flows consume zero memory.

### The Trade-Off
Process-per-instance means you need process discovery (Registry) and crash recovery (RecoveryManager). These are non-trivial additions. For a simple CRUD app, this would be over-engineering. For a flow engine with long-running stateful instances, it's the right call.

## Pattern 2: Plugin-Style Node System

### What It Is
Nodes (the building blocks of flows) are modules that implement a behaviour. They're registered in an ETS table at startup, mapping string type names to modules.

### The Registration Flow

```
Application starts
  → Engine.Supervisor starts NodeRegistry (GenServer)
    → NodeRegistry.init creates ETS table :node_registry
    → Registers 23+ built-in nodes:
        "send_email" → Kalcifer.Engine.Nodes.Action.Channel.SendEmail
        "condition"  → Kalcifer.Engine.Nodes.Condition.Condition
        "wait"       → Kalcifer.Engine.Nodes.Wait.Wait
        "ab_split"   → Kalcifer.Engine.Nodes.Condition.ABSplit
        ... etc

Runtime (optional):
  → NodeRegistry.register("custom_node", MyApp.CustomNode)
    → ETS insert, immediately available to all FlowServers
```

### Why ETS Instead of a Map in a GenServer?

A GenServer holding a `%{"send_email" => module}` map would work, but every node lookup would serialize through that GenServer's mailbox. With 5,000 flow instances all executing nodes concurrently, that's a bottleneck.

ETS with `read_concurrency: true` allows parallel reads. All 5,000 FlowServers can look up node modules simultaneously without contention.

### The NodeBehaviour Contract

```elixir
# Every node must answer these questions:
# 1. What happens when you execute? (execute/2)
# 2. What happens when you resume after waiting? (resume/3, optional)
# 3. Is your config valid? (validate/1, optional)
# 4. What config do you accept? (config_schema/0)
# 5. What category are you? (category/0)

# Return types enforce a protocol:
{:completed, result}        # Done, move to next node
{:branched, branch_key, result}  # Done, follow a specific edge
{:waiting, wait_config}     # Pause, resume later
{:failed, reason}           # Error, mark instance as failed
```

### Why This Matters
Adding a new node type (say, "send_telegram") requires:
1. Create a module implementing NodeBehaviour
2. Register it: `NodeRegistry.register("send_telegram", MyNode)`
3. Done. No framework changes, no recompilation of existing code.

Flow graphs (JSON) reference nodes by string type. The executor looks up the module at runtime via ETS. This is the Open/Closed Principle implemented via processes and ETS.

## Pattern 3: Event-Driven Resumption

### The Problem
A flow instance is waiting for an external event (e.g., "customer clicked email link"). The event could arrive in 5 seconds or 5 days. You can't keep a process alive for 5 days just waiting.

### The Solution: Three-Layer Resumption

**Layer 1: EventRouter (immediate, in-memory)**
```
External event arrives (POST /api/v1/events)
  → EventRouter queries FlowInstances in "waiting" status
    → Finds instances where context["_waiting_event_type"] matches
    → If FlowServer process is alive: GenServer.cast({:resume, ...})
    → If not alive: schedule Oban ResumeFlowJob
```

**Layer 2: Oban ResumeFlowJob (delayed, persistent)**
```
Wait node with duration (e.g., "wait 3 hours")
  → FlowServer persists state, terminates
  → Oban job scheduled_at = now + 3h
  → After 3h: job starts new FlowServer, loads state, continues
```

**Layer 3: RecoveryManager (crash recovery, on boot)**
```
Application starts
  → RecoveryManager queries DB for instances with status "waiting" or "running"
    → "waiting" instances: start FlowServer, ready for resume
    → "running" instances: mark as "crashed" (they were mid-execution when the app died)
```

### Why Three Layers?
- EventRouter handles the hot path (events for live processes)
- Oban handles the cold path (scheduled delays, processes that terminated)
- RecoveryManager handles the failure path (application crash/restart)

Together, no event is ever lost, and no instance is ever stuck.

## Pattern 4: Circuit Breaker for Channel Delivery

### The Problem
Kalcifer sends messages through external channels (email API, SMS gateway, push notification service). These services go down. Without protection, Kalcifer would keep trying to send, queueing up failures, and potentially DDOSing a struggling service.

### The Implementation

```
Circuit Breaker States:
  CLOSED (normal) → failures < threshold → allow all requests
  OPEN (tripped)  → failures >= threshold → block requests, return error immediately
  HALF_OPEN       → after cooldown → allow ONE test request
    → If succeeds: back to CLOSED
    → If fails: back to OPEN

Per-Channel Tracking:
  email:     CLOSED (0 failures)
  sms:       OPEN (5 failures, cooldown 30s)
  push:      CLOSED (2 failures)
  whatsapp:  HALF_OPEN (testing)
```

### Why Per-Channel?
If the email provider is down, SMS and push should still work. Global circuit breaking would kill all channels because of one provider's outage.

### How It Fits in the Execution Flow

```
FlowServer reaches send_email node
  → NodeExecutor calls CircuitBreaker.check(:email)
    → If CLOSED: proceed with delivery
      → If delivery fails: CircuitBreaker.record_failure(:email)
      → If delivery succeeds: CircuitBreaker.record_success(:email)
    → If OPEN: return {:error, :circuit_open}
      → FlowServer can retry later (via Oban) or skip
```

## Pattern 5: Generic Context Accumulation

### What It Is
Every FlowInstance carries a `context` map that accumulates results as execution progresses through nodes.

```elixir
# Initial context (set at trigger time)
%{
  "_customer_id" => "cust_abc",
  "_flow_id" => "flow_123",
  "_tenant_id" => "tenant_456",
  "trigger_data" => %{"source" => "signup_form"}
}

# After send_email node
%{
  "_customer_id" => "cust_abc",
  # ... previous keys ...
  "accumulated" => %{
    "send_email_1" => %{"message_id" => "msg_789", "status" => "delivered"}
  }
}

# After condition node (checks if email was opened)
%{
  # ... previous keys ...
  "accumulated" => %{
    "send_email_1" => %{"message_id" => "msg_789", "status" => "delivered"},
    "condition_1" => %{"result" => true, "branch" => "opened"}
  }
}
```

### Why a Generic Map?
- Nodes don't need to know about each other's data structures
- New node types can add any data to context
- Conditions can read any previous node's results
- No schema coupling between nodes

### Reserved Keys (Prefixed with `_`)
```
_customer_id        — who this instance is for
_flow_id            — which flow
_tenant_id          — which tenant
_instance_id        — this instance's ID
_waiting_event_type — what event would resume this instance
_waiting_node_id    — which node is waiting
_waiting_node_type  — type of waiting node
_resume_scheduled_at — when the resume job fires
_dry_run            — if true, nodes skip side effects
```

### The Dry Run Pattern
Setting `_dry_run: true` in context makes nodes skip external side effects (no emails sent, no webhooks called, no API calls) while still producing results. This is used for: testing flows before activation, validating graph execution paths, and debugging production flows without side effects.

## Pattern 6: Supervision Tree Design

### Kalcifer's Full Supervision Tree

```
Application Supervisor (one_for_one)
  ├── Kalcifer.Repo (Ecto connection pool)
  ├── Phoenix.PubSub (inter-process messaging)
  ├── Finch (HTTP client pool)
  ├── Oban (job queue)
  ├── KalciferWeb.Endpoint (HTTP server)
  └── Kalcifer.Engine.Supervisor (rest_for_one)  ← THE ENGINE
        ├── 1. LogCollector
        ├── 2. Registry (ProcessRegistry, unique keys)
        ├── 3. NodeRegistry (ETS, built-in nodes)
        ├── 4. ProviderRegistry (ETS, channel providers)
        ├── 5. Analytics.Collector
        ├── 6. CircuitBreaker
        ├── 7. DynamicSupervisor (FlowSupervisor)
        │     ├── FlowServer (instance_abc)
        │     ├── FlowServer (instance_def)
        │     └── ... (thousands possible)
        └── 8. RecoveryManager (Task)
```

### Why rest_for_one for the Engine?

The children have dependencies flowing downward:
- FlowSupervisor needs NodeRegistry (to look up node modules) and ProcessRegistry (to register FlowServer names)
- RecoveryManager needs FlowSupervisor (to start recovered instances)

If NodeRegistry crashes:
1. NodeRegistry restarts (ETS table recreated, nodes re-registered)
2. Everything AFTER NodeRegistry also restarts (ProviderRegistry, Analytics, CircuitBreaker, FlowSupervisor, RecoveryManager)
3. All FlowServer processes are terminated and recreated by RecoveryManager from DB state

This guarantees consistency: no FlowServer ever runs with stale registry data.

### Why one_for_one at the top level?

Repo, PubSub, Oban, and the Engine are independent. If Oban crashes, we don't need to restart the HTTP endpoint. Independent components use one_for_one.

## Pattern 7: Multi-Tenancy via Context

### The Pattern
Every API request extracts the tenant from the Bearer token. Every context function receives `tenant_id` as the first parameter. Every query filters by `tenant_id`.

```
Request → ApiKeyAuth plug → conn.assigns.current_tenant → Controller → Context(tenant_id, ...) → Query(WHERE tenant_id = ?)
```

### What This Means Architecturally
- No database-level isolation (no separate schemas or databases per tenant)
- Row-level isolation via query scoping
- Tenant context propagated through Logger metadata for observability
- Rate limiting is per-tenant (ETS-based counter)

### The Trade-Off
Database-per-tenant gives stronger isolation but is operationally expensive (migrations, connections, backups per tenant). Row-level scoping is simpler but requires discipline — every query must filter by tenant_id. Kalcifer's context-module pattern (always passing tenant_id) makes this discipline structural rather than relying on developers remembering.

## Pattern 8: Graph-as-Data

### The Pattern
Flow definitions are JSON documents stored in flow_versions.graph:

```json
{
  "nodes": [
    {"id": "entry_1", "type": "event_entry", "config": {"event_type": "signup"}},
    {"id": "email_1", "type": "send_email", "config": {"template": "welcome"}},
    {"id": "wait_1", "type": "wait", "config": {"duration": "3d"}},
    {"id": "check_1", "type": "condition", "config": {"field": "email_opened"}},
    {"id": "exit_1", "type": "exit", "config": {}}
  ],
  "edges": [
    {"from": "entry_1", "to": "email_1"},
    {"from": "email_1", "to": "wait_1"},
    {"from": "wait_1", "to": "check_1"},
    {"from": "check_1", "to": "exit_1", "branch": "default"}
  ]
}
```

### Why Not BPMN, BPEL, or a DSL?
- JSON is universally parseable (frontend editors, API clients, CLI tools)
- No special parser or compiler needed
- Simple structure: nodes have type + config, edges connect nodes
- Branch routing via edge `branch` field matches node `branch_key` output
- GraphWalker is ~100 lines of code, not a complex interpreter

### Graph Execution Model

```
GraphWalker.find_entry_nodes(graph)  → [entry_1]
GraphWalker.next_nodes(graph, "entry_1")  → [email_1]
GraphWalker.next_nodes(graph, "email_1")  → [wait_1]
GraphWalker.next_nodes(graph, "check_1", branch: "opened")  → [followup_email]
GraphWalker.next_nodes(graph, "check_1", branch: "default")  → [exit_1]
```

### Safety Limits
FlowServer enforces a max execution count (200 steps) to prevent infinite loops in cyclic graphs. This is a hard limit, not configurable per flow.

## Connecting the Patterns

Here's a complete flow execution showing all patterns working together:

```
1. POST /api/v1/trigger/flow_123 {customer_id: "cust_1"}
   → [Multi-Tenancy] ApiKeyAuth extracts tenant from Bearer token
   → [Multi-Tenancy] Controller passes tenant_id to Engine

2. Engine.trigger_flow(tenant_id, flow_id, customer_id, context)
   → [Ecto] Create FlowInstance record in DB
   → [Process-Per-Instance] DynamicSupervisor.start_child(FlowServer)

3. FlowServer.init/1
   → [Graph-as-Data] Load graph JSON from FlowVersion
   → [Generic Context] Initialize context with customer_id, tenant_id, etc.
   → [Graph-as-Data] Find entry node via GraphWalker

4. Execute "send_email" node
   → [Plugin System] NodeRegistry.lookup("send_email") → SendEmail module
   → [Circuit Breaker] Check email circuit → CLOSED → proceed
   → [Channel Delivery] SendMessageJob inserted via Oban
   → [Generic Context] Accumulate result: {message_id, status}

5. Execute "wait" node (wait 3 days)
   → [Ecto] Persist instance state (status: "waiting", context with node_id)
   → [Oban] Schedule ResumeFlowJob at now + 3 days
   → [Process-Per-Instance] FlowServer terminates (frees memory)

6. 3 days later: Oban fires ResumeFlowJob
   → [Process-Per-Instance] Start new FlowServer
   → [Ecto] Load state from DB
   → [Event-Driven Resumption] Continue from wait node

7. Execute "condition" node
   → [Plugin System] NodeRegistry.lookup("condition") → Condition module
   → [Generic Context] Read accumulated results to evaluate condition
   → Returns {:branched, "opened", result}
   → [Graph-as-Data] GraphWalker follows "opened" branch edge

8. Execute "exit" node
   → [Ecto] Set instance status to "completed"
   → [Process-Per-Instance] FlowServer terminates normally
```

## Anti-Patterns to Avoid

1. **Putting business logic in controllers**: Controllers dispatch to contexts. Contexts dispatch to the engine. The engine executes nodes. Each layer has a clear responsibility.

2. **Sharing state between FlowServer processes via ETS**: FlowServers are isolated. If they need to coordinate, use PubSub events or database queries, not shared mutable state.

3. **Synchronous channel delivery in node execution**: Sending an email can take seconds. Kalcifer delegates delivery to Oban jobs so node execution isn't blocked.

4. **Relying on process state as source of truth**: The database is the source of truth. Process state is a cache that's rebuilt on restart. Always persist before responding.

5. **Building monolithic nodes**: Each node should do one thing. "SendEmailAndUpdateProfile" should be two nodes. The graph structure handles composition.

## Recommended Resources

- "Designing Elixir Systems with OTP" by James Edward Gray II & Bruce Tate
- "Building Microservices" by Sam Newman (for distributed patterns context)
- Martin Fowler's "Circuit Breaker" pattern article
- Elixir Forum discussions on DynamicSupervisor patterns
- Saša Jurić's talks on BEAM concurrency (YouTube)
