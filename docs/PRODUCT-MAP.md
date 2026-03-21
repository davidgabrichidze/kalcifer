# Kalcifer — Product Map

> საბოლოო პროდუქტის ჩონჩხი. ყოველი `feat`/`fix` კომიტი ამ ხიდან იღებს scope-ს.

```
feat(engine/nodes): add rate_limit node
fix(api/instances): correct timeline ordering
feat(ai/tools): implement create_flow tool
      │    │
      │    └─ Level 2 (subscope)
      └────── Level 1 (scope)
```

---

## The Tree

```
kalcifer
│
├── engine                          # Flow execution core (OTP)
│   ├── executor                    # ✅ FlowServer, NodeExecutor, GraphWalker, DryRun
│   ├── nodes                       # ✅ 22 built-in node types (see Node Map below)
│   ├── events                      # ✅ EventRouter, EventBroadcaster
│   ├── recovery                    # ✅ RecoveryManager, crash recovery on boot
│   ├── persistence                 # ✅ InstanceStore, StepStore
│   ├── jobs                        # ✅ ResumeFlowJob, CleanupJob, StatsRollupJob
│   ├── errors                      # ✅ ErrorCatalog, humanized error messages
│   └── circuit-breaker             # ✅ CircuitBreaker for external calls
│
├── flows                           # Flow data model & lifecycle
│   ├── lifecycle                   # ✅ CRUD, activate → pause → archive
│   ├── versions                    # ✅ FlowVersion, migration, rollback
│   ├── graph                       # ✅ FlowGraph validation, config analysis, context deps
│   └── instances                   # ✅ FlowInstance, timeline, cancel
│
├── channels                        # Message delivery infrastructure
│   ├── providers                   # ⚠️ ProviderRegistry + Log/Webhook only (no real providers)
│   ├── delivery                    # ✅ ChannelSender, Delivery tracking, status callbacks
│   └── webhooks                    # ✅ Inbound webhook processing (SendGrid, Twilio stubs)
│
├── customers                       # Customer data layer
│   ├── profiles                    # ✅ Customer CRUD, tags, preferences
│   └── segments                    # ✅ Segment definitions, SegmentEvaluator
│
├── analytics                       # Metrics & insights
│   ├── stats                       # ✅ FlowStats, NodeStats, Collector, rollup
│   ├── funnel                      # ✅ Funnel analysis
│   └── conversions                 # ✅ Conversion tracking, A/B results
│
├── marketing                       # Journey layer (marketing wrapper on flows)
│   └── journeys                    # ✅ Journey CRUD, launch/pause/archive
│
├── tenants                         # Multi-tenancy
│   └── auth                        # ✅ API key SHA256 hashing, Bearer token lookup
│
├── api                             # REST API (Phoenix)
│   ├── flows                       # ✅ CRUD + activate/pause/archive/preflight
│   ├── versions                    # ✅ index/create/show + migrate/rollback/status
│   ├── instances                   # ✅ index/show/timeline/cancel
│   ├── triggers                    # ✅ trigger flow, send event
│   ├── customers                   # ✅ CRUD + tags + preferences
│   ├── analytics                   # ✅ summary/nodes/funnel/ab_results
│   ├── journeys                    # ✅ CRUD + launch/pause/archive
│   ├── health                      # ✅ health check, metrics
│   └── middleware                  # ✅ ApiKeyAuth, RateLimiter
│
├── ws                              # WebSocket layer (Phoenix Channels)
│   ├── monitoring                  # ✅ FlowChannel — real-time instance/step events
│   └── presence                    # ❌ Online operators, live cursors
│
├── ai                              # AI core — კალციფერის ტვინი
│   ├── chat                        # ❌ Claude API client, streaming SSE
│   ├── tools                       # ❌ AI tool definitions (create_flow, diagnose, etc.)
│   ├── context                     # ❌ Context assembly — flow state, analytics, errors
│   └── prompts                     # ❌ System prompt, persona, tool schemas
│
├── simulators                      # Provider simulators (before real providers)
│   ├── email                       # ❌ Email simulator (delays, bounces, opens, clicks)
│   ├── sms                         # ❌ SMS simulator (delivery, failures)
│   ├── push                        # ❌ Push notification simulator
│   ├── whatsapp                    # ❌ WhatsApp simulator (read receipts, replies)
│   └── in-app                      # ❌ In-app message simulator
│
├── fe                              # Frontend (React SPA)
│   ├── shell                       # 🔨 App shell, routing, splash screen
│   ├── design                      # ❌ Design system — 12 themes, tokens, components
│   ├── chat                        # ❌ AI chat panel (persistent, contextual)
│   ├── work                        # ❌ Work page — dashboard + AI assistant
│   ├── editor                      # ❌ Flow editor — visual canvas + node palette
│   ├── engine-room                 # ❌ Engine monitoring — live instances, logs
│   └── browse                      # ❌ Flow library — search, templates, import/export
│
└── infra                           # Infrastructure & operations
    ├── docker                      # ✅ docker-compose.dev.yml (app + db + frontend)
    ├── ci                          # ⚠️ mix precommit (no GitHub Actions yet)
    └── release                     # ✅ Release tasks (migrations)
```

**Legend**: ✅ done — ⚠️ partial — 🔨 in progress — ❌ not started

---

## Node Map

> `engine/nodes` scope — 22 registered types across 5 categories

```
engine/nodes
├── trigger
│   ├── event_entry                 # ✅ Flow starts when event fires
│   ├── segment_entry               # ✅ Flow starts when customer enters segment
│   └── webhook_entry               # ✅ Flow starts from external webhook
│
├── condition
│   ├── condition                   # ✅ If/else branching on context expressions
│   ├── ab_split                    # ✅ Random A/B/N split with percentages
│   ├── frequency_cap              # ✅ Skip if customer exceeded message limit
│   ├── check_segment              # ✅ Branch based on segment membership
│   └── preference_gate            # ✅ Branch based on customer preferences
│
├── action/channel
│   ├── send_email                  # ✅ Send email via provider
│   ├── send_sms                    # ✅ Send SMS via provider
│   ├── send_push                   # ✅ Send push notification via provider
│   ├── send_whatsapp              # ✅ Send WhatsApp message via provider
│   ├── send_in_app                # ✅ Send in-app message via provider
│   └── call_webhook               # ✅ HTTP call to external service
│
├── action/data
│   ├── update_profile              # ✅ Update customer profile fields
│   ├── add_tag                     # ✅ Add tags to customer
│   ├── custom_code                 # ✅ Execute custom Elixir expression
│   └── track_conversion           # ✅ Record conversion event
│
├── wait
│   ├── wait                        # ✅ Delay for duration (e.g. "3d", "2h")
│   ├── wait_until                  # ✅ Wait until specific datetime
│   └── wait_for_event             # ✅ Pause until matching event arrives
│
└── end
    ├── exit                        # ✅ Normal flow termination
    └── goal_reached               # ✅ Flow completed with goal conversion
```

---

## Scope Reference

> commit format: `type(scope/subscope): description`

| scope | subscopes |
|-------|-----------|
| `engine` | `executor`, `nodes`, `events`, `recovery`, `persistence`, `jobs`, `errors`, `circuit-breaker` |
| `flows` | `lifecycle`, `versions`, `graph`, `instances` |
| `channels` | `providers`, `delivery`, `webhooks` |
| `customers` | `profiles`, `segments` |
| `analytics` | `stats`, `funnel`, `conversions` |
| `marketing` | `journeys` |
| `tenants` | `auth` |
| `api` | `flows`, `versions`, `instances`, `triggers`, `customers`, `analytics`, `journeys`, `health`, `middleware` |
| `ws` | `monitoring`, `presence` |
| `ai` | `chat`, `tools`, `context`, `prompts` |
| `simulators` | `email`, `sms`, `push`, `whatsapp`, `in-app` |
| `fe` | `shell`, `design`, `chat`, `work`, `editor`, `engine-room`, `browse` |
| `infra` | `docker`, `ci`, `release` |

Examples:
```
feat(engine/nodes): add rate_limit node
fix(api/instances): correct timeline ordering
feat(ai/tools): implement create_flow tool
feat(fe/design): add hearth theme tokens
feat(simulators/email): simulate bounce and open events
refactor(channels/providers): extract common provider interface
test(flows/graph): add property tests for cycle detection
feat(fe/chat): implement streaming message display
fix(engine/executor): handle nil context in resume
feat(ws/presence): track online operators per flow
```
