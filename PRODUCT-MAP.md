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
│   ├── nodes                       # ✅ 31 built-in node types (see Node Map below)
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
│   ├── providers                   # ✅ Log, Webhook, SendGrid, Twilio + ProviderRegistry
│   ├── delivery                    # ✅ ChannelSender, Delivery tracking + events, CircuitBreaker
│   └── webhooks                    # ✅ Inbound webhooks with signature verification
│
├── customers                       # Customer data layer
│   ├── profiles                    # ✅ Customer CRUD, tags, preferences
│   └── segments                    # ✅ Segment CRUD API, DB-level evaluation, engine wiring
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
│   └── presence                    # ✅ Online operators (Phoenix.Presence, editor indicator)
│
├── ai                              # AI core — კალციფერის ტვინი
│   ├── chat                        # ✅ Claude API client (Finch streaming), SSE endpoint
│   ├── tools                       # ✅ 13 tools (flow CRUD, graph editing, analysis, debug, memory)
│   ├── context                     # ✅ Conversations (persistent, classified), Memory (CRUD, auto-load)
│   └── prompts                     # ✅ System prompt with Calcifer personality (Georgian)
│
├── simulators                      # Provider simulators (before real providers)
│   ├── email                       # ✅ Email simulator (delays, bounces, opens, clicks)
│   ├── sms                         # ✅ SMS simulator (delivery, carrier failures)
│   ├── push                        # ✅ Push simulator (delivery, taps, invalid tokens)
│   ├── whatsapp                    # ✅ WhatsApp simulator (read receipts, replies)
│   └── in-app                      # ✅ In-app simulator (session delivery, seen, expiry)
│
├── fe                              # Frontend (React SPA)
│   ├── shell                       # ✅ App shell, routing, TopBar, splash screen
│   ├── design                      # ✅ Themes, tokens, dark mode
│   ├── chat                        # ✅ ChatPanel (streaming, markdown, activity, persistence)
│   ├── work                        # ✅ Work page (sidebar, chat, context panel, inline editor)
│   ├── editor                      # ✅ Flow editor (canvas, palette, groups, sim/live modes)
│   ├── engine-room                 # ✅ Engine Room (stats, logs, channels, API keys)
│   └── browse                      # ✅ Browse (flows, instances, timelines, export/import)
│
└── infra                           # Infrastructure & operations
    ├── docker                      # ✅ docker-compose.yml one-command + dev/prod variants
    ├── ci                          # ✅ GitHub Actions (CI, release, docker publish)
    └── release                     # ✅ Release tasks (migrations)
```

**Legend**: ✅ done — ⚠️ partial — 🔨 in progress — ❌ not started

---

## Node Map

> `engine/nodes` scope — 31 registered types across 5 categories (includes 4 AI + 4 orchestration nodes)

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
├── action/ai
│   ├── ai_think                    # ✅ AI generates text/analysis from flow context
│   ├── ai_decide                   # ✅ AI-powered branching (condition via Claude)
│   ├── ai_notify                   # ✅ AI-summarized operator notifications (PubSub)
│   ├── agent                       # ✅ Multi-round tool-using agent node
│   └── flow_router                 # ✅ AI picks a route to a sub-flow
│
├── action/orchestration
│   ├── parallel_group              # ✅ Run branches in parallel (Task.async_stream)
│   ├── sub_flow                    # ✅ Run another flow as a child instance
│   └── memory_recall               # ✅ Recall operator memories into context
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
