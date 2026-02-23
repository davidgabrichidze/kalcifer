# Phase 1: Production Readiness

## Phase 0 Recap

Phase 0-ში აიგო Kalcifer-ის core engine:

- **24 node type** (3 entry, 5 condition, 3 wait, 6 channel, 4 data, 2 exit)
- **GenServer-based execution** — FlowServer per instance, DynamicSupervisor, Registry
- **Live Version Migration** — hot-swap, rollback, NodeMapper, Migrator
- **Multi-tenant API** — Bearer token auth, tenant isolation, Phoenix controllers
- **Recovery** — RecoveryManager restores waiting instances on boot
- **407 tests, 0 failures** (7 properties, 11 known_bug excluded)

### რა არის stub/placeholder:

| დირექტორია | სტატუსი |
|---|---|
| `lib/kalcifer/channels/providers/` | ცარიელი — channel node-ები stub-ია |
| `lib/kalcifer/analytics/` | ცარიელი |
| `lib/kalcifer/customers/` | ცარიელი |
| `lib/kalcifer/sandbox/` | ცარიელი |
| `lib/kalcifer/auth/` | ცარიელი — Guardian imported, not configured |
| Broadway | imported, not used |
| Telemetry | configured, minimal |

### გამოუსწორებელი ბაგები (11 test, 7 file):

| კოდი | ბაგი | სიმძიმე |
|------|------|---------|
| C1 | EventRouter — cross-tenant event injection | **Critical/Security** |
| C3 | ResumeFlowJob returns `:ok` for dead process | Critical |
| C6/I13 | wait_until migration — wrong atom + missing arm | Critical |
| C9 | nil customer_id bypasses dedup, crashes Ecto | High |
| I1 | FlowInstance.status_changeset — no state machine | High |
| I5 | Invalid migration strategy → 500 crash | Medium |
| T5 | same_version migration → 500 (FallbackController) | Medium |
| N4 | AbSplit empty variants → FunctionClauseError | Medium |

---

## Phase 1 Overview

```
Increment 12: Bug Fixes & Input Validation
Increment 13: Channel Provider Architecture
Increment 14: Customer Data Model
Increment 15: Analytics Foundation
Increment 16: Real-time Monitoring (PubSub + WebSocket)
Increment 17: Production Hardening (Rate Limiting, Observability, Error Handling)
```

---

## Increment 12: Bug Fixes & Input Validation

**Goal**: გამოვასწოროთ ყველა known_bug, დავამატოთ input validation.

### 12a: Security & Critical Fixes

**C1: Cross-tenant event isolation**

EDIT `lib/kalcifer/engine/event_router.ex`:
- `route_event/3` → `route_event/4` — დავამატოთ `tenant_id` პარამეტრი
- `InstanceStore.list_waiting_for_customer/1` → `list_waiting_for_customer/2` — tenant_id filter

EDIT `lib/kalcifer/engine/persistence/instance_store.ex`:
- `list_waiting_for_customer(customer_id)` → `list_waiting_for_customer(tenant_id, customer_id)`
- WHERE clause-ში `tenant_id` filter

EDIT `lib/kalcifer_web/controllers/event_controller.ex`:
- `EventRouter.route_event(customer_id, ...)` → `EventRouter.route_event(tenant.id, customer_id, ...)`

Remove `@tag :known_bug` from `cross_tenant_event_test.exs`

**C3: ResumeFlowJob dead process handling**

EDIT `lib/kalcifer/engine/jobs/resume_flow_job.ex`:
- Process dead → `{:snooze, 30}` ნაცვლად `:ok`-ის
- Max attempts-ის შემდეგ → mark instance as crashed

Remove `@tag :known_bug` from `resume_job_dead_process_test.exs`

**C6/I13: wait_until migration**

EDIT `lib/kalcifer/versioning/node_mapper.ex`:
- `detect_wait_changes` — `wait_until` → `:datetime_changed` (არა `:duration_changed`)

EDIT `lib/kalcifer/engine/flow_server.ex`:
- `apply_wait_change` — `"wait_until"` arm: cancel old job + `schedule_at` new datetime

Remove `@tag :known_bug` from `wait_until_migration_test.exs`

**C9: nil customer_id validation**

EDIT `lib/kalcifer_web/controllers/trigger_controller.ex`:
- Validate `customer_id` presence before processing

EDIT `lib/kalcifer_web/controllers/event_controller.ex`:
- Validate `customer_id` და `event_type` presence

Tests: update `nil_customer_id_test.exs`

### 12b: State Machine & Validation Fixes

**I1: FlowInstance status transitions**

EDIT `lib/kalcifer/flows/flow_instance.ex`:
- `status_changeset/3` — state machine validation:
  ```
  running  → waiting, completed, failed, paused
  waiting  → running, completed, failed, paused, exited
  paused   → running, exited
  completed, failed, exited → (terminal, no transitions)
  ```

Remove `@tag :known_bug` from `instance_status_transition_test.exs`

**N4: AbSplit empty variants**

EDIT `lib/kalcifer/engine/nodes/condition/ab_split.ex`:
- `execute/2` — empty/missing variants → `{:failed, :no_variants}`

Remove `@tag :known_bug` from `ab_split_empty_variants_test.exs`

**I5: Invalid migration strategy**

EDIT `lib/kalcifer_web/controllers/migration_controller.ex`:
- Validate `strategy` ∈ `["new_entries_only", "migrate_all"]`
- Invalid → 422 response

Remove `@tag :known_bug` from `invalid_migration_strategy_test.exs`

**T5: same_version fallback**

EDIT `lib/kalcifer_web/controllers/fallback_controller.ex`:
- `:same_version` error clause → 409 Conflict

Remove `@tag :known_bug` from `same_version_migration_test.exs`

### 12c: Tests

- ყველა `@tag :known_bug` უნდა წაიშალოს (11 test)
- 0 excluded tests
- **მოსალოდნელი: ~407 tests, 0 failures, 0 excluded**

---

## Increment 13: Channel Provider Architecture

**Goal**: stub channel node-ები რეალურ provider-ებთან დავაკავშიროთ.

### 13a: Provider Behaviour & Registry

CREATE `lib/kalcifer/channels/provider.ex`:
```elixir
@callback send_message(channel :: atom(), recipient :: map(), message :: map(), opts :: map()) ::
  {:ok, delivery_id :: String.t()} | {:error, reason :: term()}

@callback delivery_status(delivery_id :: String.t()) ::
  {:ok, status :: String.t()} | {:error, reason :: term()}
```

CREATE `lib/kalcifer/channels/provider_registry.ex`:
- GenServer + ETS — channel type → provider module mapping
- Runtime-configurable: `config :kalcifer, :channel_providers, email: Kalcifer.Channels.Providers.SendGrid`

CREATE `lib/kalcifer/channels/delivery.ex` (schema):
- `id`, `instance_id`, `step_id`, `channel`, `recipient`, `provider`, `provider_message_id`
- `status` (pending → sent → delivered → bounced → failed)
- `sent_at`, `delivered_at`, `failed_at`, `error`

Migration: `create_deliveries` table

Tests: ~8 tests (provider behaviour, registry, delivery schema)

### 13b: Provider Implementations

CREATE `lib/kalcifer/channels/providers/log_provider.ex`:
- Development/test provider — logs message, returns fake delivery_id
- Default provider for all channels

CREATE `lib/kalcifer/channels/providers/webhook_provider.ex`:
- Generic HTTP POST provider — `Req.post(url, json: payload)`
- Retry with exponential backoff (Oban job)
- HMAC signature header

CREATE `lib/kalcifer/channels/providers/sendgrid.ex`:
- SendGrid API integration (email)
- Template rendering via template_id

CREATE `lib/kalcifer/channels/providers/twilio.ex`:
- Twilio API (SMS, WhatsApp)

Tests: ~12 tests (log provider unit, webhook provider with bypass, mock providers)

### 13c: Channel Node Integration

EDIT channel node-ები (send_email, send_sms, send_push, send_whatsapp, send_in_app, call_webhook):
- `execute/2` → ProviderRegistry-დან provider lookup
- `provider.send_message(channel, recipient, message, opts)`
- Result → delivery record + `{:completed, %{delivery_id: id}}`

CREATE `lib/kalcifer/channels/jobs/send_message_job.ex` (Oban worker):
- Async message sending — queue: `:channel_delivery`
- Retry logic, dead letter

EDIT `config/config.exs`:
- Oban queue: `channel_delivery: 50`
- Default providers config

Tests: ~10 tests (integration with log provider, delivery tracking)

### 13d: Delivery Webhooks (Inbound)

CREATE `lib/kalcifer_web/controllers/webhook_controller.ex`:
- `POST /api/v1/webhooks/sendgrid` — delivery status callbacks
- `POST /api/v1/webhooks/twilio` — SMS delivery receipts
- Signature verification per provider

EDIT `lib/kalcifer_web/router.ex`:
- Webhook routes (unauthenticated, signature-verified)

Tests: ~6 tests

**Increment 13 Total: ~36 tests, ~12 files**

---

## Increment 14: Customer Data Model

**Goal**: customer profiles, segments, preferences — condition node-ებისთვის რეალური data.

### 14a: Customer Schema & CRUD

CREATE `lib/kalcifer/customers/customer.ex`:
- `id`, `tenant_id`, `external_id` (unique per tenant)
- `email`, `phone`, `name`
- `properties` (map — arbitrary attributes)
- `tags` (array of strings)
- `preferences` (map — email_opt_in, sms_opt_in, push_opt_in)
- `created_at`, `last_seen_at`

CREATE `lib/kalcifer/customers.ex` (context):
- CRUD, upsert by external_id, tag management, preference management

Migration: `create_customers` table + indexes

CREATE `lib/kalcifer_web/controllers/customer_controller.ex`:
- `GET/POST/PUT /api/v1/customers`
- `POST /api/v1/customers/:id/tags`
- `PUT /api/v1/customers/:id/preferences`

EDIT `lib/kalcifer_web/router.ex`: customer routes

Tests: ~15 tests (CRUD, upsert, tags, preferences)

### 14b: Segment Engine

CREATE `lib/kalcifer/customers/segment.ex` (schema):
- `id`, `tenant_id`, `name`, `description`
- `rules` (map — filter criteria: `[{field, operator, value}]`)
- `type` — static (manual) | dynamic (rule-based)

CREATE `lib/kalcifer/customers/segment_evaluator.ex`:
- `member?(customer, segment)` — evaluates rules against customer properties
- Operators: `eq`, `neq`, `gt`, `lt`, `contains`, `in`, `not_in`

EDIT condition node-ები:
- `check_segment.ex` — `SegmentEvaluator.member?(customer, segment)`
- `preference_gate.ex` — customer preferences lookup
- `condition.ex` — customer properties lookup

Tests: ~12 tests (segment rules, evaluator, node integration)

### 14c: Customer Context Enrichment

EDIT `lib/kalcifer/engine/flow_trigger.ex`:
- Trigger-ზე customer lookup/upsert
- Context enrichment: `_customer` map in flow context

EDIT `lib/kalcifer/engine/flow_server.ex`:
- `init/1` — customer data loaded into context

EDIT data action node-ები:
- `update_profile.ex` — `Customers.update(customer, fields)`
- `add_tag.ex` — `Customers.add_tag(customer, tag)`

Tests: ~8 tests (enrichment, data actions)

**Increment 14 Total: ~35 tests, ~10 files**

---

## Increment 15: Analytics Foundation

**Goal**: flow execution analytics, conversion tracking, A/B test results.

### 15a: Event Store & Aggregation

CREATE `lib/kalcifer/analytics/flow_stats.ex` (schema):
- `flow_id`, `version_number`, `date`
- `entered`, `completed`, `failed`, `exited` (counters)
- `avg_completion_time_seconds`
- Unique constraint: `{flow_id, version_number, date}`

CREATE `lib/kalcifer/analytics/node_stats.ex` (schema):
- `flow_id`, `version_number`, `node_id`, `date`
- `executed`, `completed`, `failed` (counters)
- `branch_counts` (map — branch_key → count)
- Unique constraint: `{flow_id, version_number, node_id, date}`

CREATE `lib/kalcifer/analytics/collector.ex`:
- Telemetry handler — listens to `[:kalcifer, :step, :complete]` events
- Batched upserts (GenServer with periodic flush)

EDIT `lib/kalcifer/engine/flow_server.ex`:
- Telemetry events: `:telemetry.execute([:kalcifer, :step, :complete], measurements, metadata)`

Migration: `create_flow_stats`, `create_node_stats` tables

Tests: ~10 tests (collector batching, stats aggregation)

### 15b: Analytics API

CREATE `lib/kalcifer/analytics.ex` (context):
- `flow_summary(flow_id, date_range)` — entered/completed/failed/conversion
- `node_breakdown(flow_id, version, date_range)` — per-node stats
- `ab_test_results(flow_id, node_id, date_range)` — variant → conversion map
- `funnel(flow_id, node_path)` — drop-off at each step

CREATE `lib/kalcifer_web/controllers/analytics_controller.ex`:
- `GET /api/v1/flows/:flow_id/analytics/summary`
- `GET /api/v1/flows/:flow_id/analytics/nodes`
- `GET /api/v1/flows/:flow_id/analytics/funnel`
- `GET /api/v1/flows/:flow_id/nodes/:node_id/ab_results`

EDIT `lib/kalcifer_web/router.ex`: analytics routes

Tests: ~12 tests (summary, node breakdown, funnel, AB results)

### 15c: Conversion Tracking

EDIT `lib/kalcifer/engine/nodes/action/data/track_conversion.ex`:
- Real implementation — `Analytics.record_conversion(flow_id, customer_id, event)`

CREATE `lib/kalcifer/analytics/conversion.ex` (schema):
- `flow_id`, `instance_id`, `customer_id`
- `conversion_type`, `value`, `metadata`
- `converted_at`

EDIT `lib/kalcifer/engine/nodes/end/goal_reached.ex`:
- Auto-record conversion when goal node reached

Tests: ~6 tests

**Increment 15 Total: ~28 tests, ~10 files**

---

## Increment 16: Real-time Monitoring

**Goal**: PubSub events + WebSocket channel — live flow monitoring dashboard-ისთვის.

### 16a: PubSub Event Broadcasting

CREATE `lib/kalcifer/engine/event_broadcaster.ex`:
- Wraps `Phoenix.PubSub.broadcast`
- Topics: `flow:{flow_id}`, `instance:{instance_id}`, `tenant:{tenant_id}`
- Events:
  - `instance_started`, `instance_completed`, `instance_failed`
  - `node_executed`, `node_waiting`, `node_resumed`
  - `migration_started`, `migration_completed`

EDIT `lib/kalcifer/engine/flow_server.ex`:
- Broadcast at key lifecycle points (init, complete, fail, wait, resume)

Tests: ~6 tests (PubSub subscription, event format)

### 16b: WebSocket Channel

CREATE `lib/kalcifer_web/channels/flow_channel.ex`:
- `join("flow:{flow_id}", ...)` — authenticate + subscribe
- `join("tenant:{tenant_id}", ...)` — all flows for tenant
- Forwards PubSub events to connected clients

CREATE `lib/kalcifer_web/channels/user_socket.ex`:
- Token-based auth (same API key)

EDIT `lib/kalcifer_web/endpoint.ex`:
- Socket mount

Tests: ~8 tests (join, auth, event delivery)

### 16c: Instance Inspector API

CREATE `lib/kalcifer_web/controllers/instance_controller.ex`:
- `GET /api/v1/flows/:flow_id/instances` — list with filters (status, customer_id)
- `GET /api/v1/instances/:id` — detail with execution steps
- `GET /api/v1/instances/:id/timeline` — chronological step history
- `POST /api/v1/instances/:id/cancel` — graceful cancellation

EDIT `lib/kalcifer_web/router.ex`: instance routes

Tests: ~10 tests

**Increment 16 Total: ~24 tests, ~8 files**

---

## Increment 17: Production Hardening

**Goal**: rate limiting, structured logging, health checks, error handling.

### 17a: API Rate Limiting

CREATE `lib/kalcifer_web/plugs/rate_limiter.ex`:
- Token bucket per tenant (ETS-based)
- Configurable: `max_requests`, `window_seconds`
- 429 Too Many Requests response + `Retry-After` header

EDIT `lib/kalcifer_web/router.ex`:
- Rate limiter plug in API pipeline

Config: `config :kalcifer, :rate_limits, trigger: {100, 60}, events: {1000, 60}`

Tests: ~6 tests

### 17b: Structured Logging & Telemetry

CREATE `lib/kalcifer/telemetry.ex`:
- Telemetry event definitions
- `:telemetry.attach_many` handlers

EDIT key modules — structured Logger calls:
- FlowServer: `Logger.info("flow_server.started", instance_id: ..., flow_id: ...)`
- EventRouter: `Logger.info("event.routed", customer_id: ..., matched: ...)`
- RecoveryManager: `Logger.info("recovery.completed", recovered: ..., crashed: ...)`

EDIT `lib/kalcifer_web/controllers/health_controller.ex`:
- Extended metrics: Oban queue depths, active instances, delivery stats

Tests: ~4 tests

### 17c: Graceful Error Handling

EDIT `lib/kalcifer_web/controllers/fallback_controller.ex`:
- ყველა შესაძლო error atom → proper HTTP status:
  ```
  :not_found → 404
  :not_draft → 409
  :same_version → 409
  :no_active_version → 409
  :version_not_found → 404
  :already_in_flow → 409
  :flow_not_active → 422
  :invalid_strategy → 422
  :version_not_publishable → 422
  ```

EDIT `lib/kalcifer/engine/flow_server.ex`:
- Unhandled exceptions in `execute_single_node` → fail instance gracefully (not crash)

CREATE `lib/kalcifer/engine/circuit_breaker.ex`:
- Provider failure threshold → circuit open → skip channel delivery
- Half-open retry after cooldown

Tests: ~8 tests

### 17d: Oban Maintenance Jobs

CREATE `lib/kalcifer/engine/jobs/cleanup_job.ex` (Oban cron):
- Stale instance detection (running > 7 days without activity)
- Completed instance archival (> 30 days → archived partition)

CREATE `lib/kalcifer/engine/jobs/stats_rollup_job.ex` (Oban cron):
- Daily stats aggregation from execution_steps → flow_stats, node_stats

EDIT `config/config.exs`:
- Oban plugins: `Oban.Plugins.Cron` with schedules

Tests: ~6 tests

**Increment 17 Total: ~24 tests, ~10 files**

---

## Execution Order & Dependencies

```
12 (Bug Fixes)
 │
 ├── 13 (Channels) ────── 15c (Conversion Tracking)
 │                              │
 ├── 14 (Customers) ──── 15 (Analytics)
 │                              │
 └── 16 (Real-time) ──── 17 (Production)
```

**პარალელიზაცია:**
- 13 (Channels) და 14 (Customers) ერთდროულად შეიძლება — ერთმანეთზე არ არიან დამოკიდებული
- 15 (Analytics) მოითხოვს 13-ს (delivery tracking) და 14-ს (customer data)
- 16 (Real-time) შეიძლება 13/14-ის პარალელურად, მაგრამ 15-მდე უნდა
- 17 (Production) ბოლო — ყველაფერზე დამოკიდებულია

### რეკომენდებული თანმიმდევრობა:

```
Week 1:  12a → 12b → 12c (bug fixes, 0 known_bugs)
Week 2:  13a → 13b (provider architecture)
Week 3:  13c → 13d + 14a (channel integration + customer schema)
Week 4:  14b → 14c (segments + context enrichment)
Week 5:  15a → 15b (analytics collection + API)
Week 6:  15c + 16a (conversions + PubSub)
Week 7:  16b → 16c (WebSocket + instance inspector)
Week 8:  17a → 17b → 17c → 17d (production hardening)
```

---

## File Count Summary

| Increment | New Files | Edited Files | New Tests | Migration |
|-----------|-----------|-------------|-----------|-----------|
| 12 | 0 | ~10 | 0 (fix existing) | 0 |
| 13 | ~12 | ~8 | ~36 | 1 |
| 14 | ~10 | ~6 | ~35 | 1 |
| 15 | ~10 | ~4 | ~28 | 2 |
| 16 | ~8 | ~4 | ~24 | 0 |
| 17 | ~10 | ~6 | ~24 | 0 |
| **Total** | **~50** | **~38** | **~147** | **4** |

Phase 1 დასრულების შემდეგ: **~554 tests**, production-ready engine.

---

## Verification Criteria

### Increment-ის დასრულების კრიტერიუმი:

1. `mix test` — 0 failures, 0 excluded
2. `mix compile --warnings-as-errors` — 0 warnings
3. `mix credo --strict` — 0 issues
4. `mix dialyzer` — 0 errors (Phase 1-ში დავამატოთ)

### Phase 1-ის დასრულების კრიტერიუმი:

- [ ] 0 known_bug tests
- [ ] ყველა channel node რეალურ provider-თან მუშაობს (min: log + webhook)
- [ ] Customer CRUD + segments + preferences
- [ ] Analytics API — flow summary, node breakdown, AB results, funnel
- [ ] WebSocket real-time monitoring
- [ ] Rate limiting + structured logging
- [ ] Instance inspector API
- [ ] Oban maintenance jobs
- [ ] dialyzer clean
