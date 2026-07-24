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
│   ├── nodes                       # ✅ 31 registered node types (see Node Map below)
│   ├── events                      # ✅ EventRouter, EventBroadcaster
│   ├── recovery                    # ✅ RecoveryManager, crash recovery on boot
│   ├── persistence                 # ✅ InstanceStore, StepStore
│   ├── jobs                        # ✅ ResumeFlowJob, CleanupJob, StatsRollupJob
│   ├── errors                      # ✅ ErrorCatalog, humanized error messages
│   ├── circuit-breaker             # ✅ CircuitBreaker for external calls
│   └── observability               # ✅ LogCollector ring buffer, LogHandler (:logger sink)
│
├── flows                           # Flow data model & lifecycle
│   ├── lifecycle                   # ✅ CRUD, activate → pause → archive
│   ├── versions                    # ✅ FlowVersion, migration, rollback
│   ├── graph                       # ✅ FlowGraph validation, config analysis, context deps
│   └── instances                   # ✅ FlowInstance, timeline, cancel
│
├── channels                        # Message delivery infrastructure
│   ├── providers                   # ✅ Registry + Log/Webhook/SendGrid/Twilio, per-tenant selection
│   ├── delivery                    # ✅ ChannelSender, SendMessageJob, Delivery tracking, status callbacks
│   └── webhooks                    # ✅ Inbound webhook processing (SendGrid, Twilio, SSRF-guarded)
│
├── customers                       # Customer data layer
│   ├── profiles                    # ✅ Customer CRUD, tags, preferences
│   └── segments                    # ✅ Segment definitions, SegmentEvaluator
│
├── analytics                       # Metrics & insights
│   ├── stats                       # ✅ FlowStats, NodeStats, Collector, TelemetryForwarder, rollup
│   ├── funnel                      # ✅ Funnel analysis
│   └── conversions                 # ✅ Conversion tracking, A/B results
│
├── marketing                       # Journey layer (marketing wrapper on flows)
│   └── journeys                    # ✅ Journey CRUD, launch/pause/archive
│
├── tenants                         # Multi-tenancy
│   └── auth                        # ✅ API key SHA256 hashing, Bearer token lookup
│
├── accounts                        # Operator accounts (people, not tenants)
│   ├── users                       # ✅ Accounts.User, Google-linked, auto-provisions a tenant
│   └── oauth                       # ✅ Google ID token verification, JWT session, UserAuth plug
│
├── audit                           # Audit trail
│   └── log                         # ✅ Audit.Entry (actor/action/resource/details), query API
│
├── api                             # REST API (Phoenix)
│   ├── flows                       # ✅ CRUD + activate/pause/archive/preflight/export/import
│   ├── versions                    # ✅ index/create/show/update + migrate/rollback/status
│   ├── instances                   # ✅ index/show/timeline/cancel
│   ├── triggers                    # ✅ trigger flow, send event
│   ├── customers                   # ✅ CRUD + tags + preferences
│   ├── segments                    # ✅ CRUD + members
│   ├── analytics                   # ✅ summary/nodes/funnel/ab_results
│   ├── journeys                    # ✅ CRUD + launch/pause/archive
│   ├── chat                        # ✅ SSE chat endpoint streaming AI.Client
│   ├── conversations               # ✅ index/show/update/archive/delete
│   ├── settings                    # ✅ tenant settings, stats, API key regeneration
│   ├── deliveries                  # ✅ index/stats + provider status callbacks
│   ├── audit                       # ✅ audit log listing
│   ├── auth                        # ✅ POST /auth/google, GET /auth/me
│   ├── webhooks                    # ✅ inbound SendGrid/Twilio, signature-verified
│   ├── simulation                  # ✅ POST /flows/:flow_id/simulate (dry-run)
│   ├── engine                      # ✅ engine stats + recent logs (DevOnly-gated)
│   ├── tenants                     # ✅ tenant roster for the dev switcher (DevOnly-gated)
│   ├── health                      # ✅ health check, metrics
│   └── middleware                  # ⚠️ ApiKeyAuth, RateLimiter, DevOnly, WebhookSignature, UserAuth
│                                   #    (see Known Gaps — not every route is behind auth)
│
├── ws                              # WebSocket layer (Phoenix Channels)
│   ├── monitoring                  # ✅ FlowChannel — real-time instance/step events
│   └── presence                    # ✅ Online operators per flow (Phoenix.Presence)
│
├── ai                              # AI core — კალციფერის ტვინი
│   ├── chat                        # ✅ Streaming client (Finch SSE), tool-use loop, SSE endpoint
│   ├── providers                   # ✅ Anthropic (Claude), OpenAI (ChatGPT), Google (Gemini) adapters
│   ├── tools                       # ✅ 13 tools (classify, flow CRUD, node edit, analyze, debug, memory)
│   ├── context                     # ✅ Conversations (persistent, classified), Memory (CRUD, auto-load),
│   │                               #    FlowSnapshot — linked flow graph injected into the prompt
│   ├── agents                      # ✅ AgentFlows — flow templates driving Kalcifer's own work cycles
│   └── prompts                     # ✅ System prompt with Calcifer personality (Georgian)
│
├── simulators                      # Provider simulators (emulate real callbacks)
│   ├── email                       # ✅ Email simulator (delays, bounces, opens, clicks)
│   ├── sms                         # ✅ SMS simulator (delivery, failures)
│   ├── push                        # ✅ Push notification simulator
│   ├── whatsapp                    # ✅ WhatsApp simulator (read receipts, replies)
│   └── in-app                      # ✅ In-app message simulator
│
├── fe                              # Frontend (React SPA)
│   ├── shell                       # ✅ App shell, routing, TopBar, tenant switcher
│   ├── auth                        # ✅ LandingPage, Google sign-in, dev skip, token storage
│   ├── design                      # ✅ 4 palettes (hearth/command/grove/calcifer) × light+dark = 8 themes
│   ├── chat                        # ✅ ChatPanel (streaming SSE, markdown, tool badges, persistent)
│   ├── work                        # ✅ Work page (sidebar + chat + context/editor panel)
│   ├── editor                      # ✅ Flow editor — canvas, palette, node config, groups
│   ├── engine-room                 # ✅ Engine monitoring — live instances, timeline
│   └── browse                      # ✅ Flow library — search, templates, import/export
│
└── infra                           # Infrastructure & operations
    ├── docker                      # ✅ docker-compose.yml + dev/prod variants (app + db + frontend)
    ├── ci                          # ✅ GitHub Actions (ci, docker-publish, release, claude, claude-review)
    └── release                     # ✅ Release tasks (migrations)
```

**Legend**: ✅ done — ⚠️ partial — 🔨 in progress — ❌ not started

Outside the tree (supporting material, not product scopes): `learn/` (Elixir/OTP study
notes), `ui-prototype/` (static HTML design prototypes), `docs/` (planning documents).

---

## Known Gaps

> Things the tree marks ⚠️ — shipped, but not finished.

**`api/middleware`** — the router has an unauthenticated scope
(`router.ex`) that `ApiKeyAuth` never sees. Controllers in it fall back to
`KalciferWeb.TenantResolver`, whose last resort is a get-or-create **"Demo Tenant"**
with no environment guard. `DevOnly` currently covers only `/tenants` and `/engine`.
Everything else in that scope — including version updates, flow import, settings
read/write, API key regeneration, audit and delivery listings, and `/chat` — is
reachable without a Bearer token and resolves to the demo tenant. The dev frontend
depends on this, so closing it means giving the frontend a real login path first.

---

## Node Map

> `engine/nodes` scope — 31 registered types, grouped below by purpose. The engine's own
> five categories come from each node's `category/0` (`:trigger | :condition | :wait |
> :action | :end`) and do not always match the grouping — `flow_router` sits with the AI
> nodes but reports `:condition`. Registry keys are the source of truth
> (`Kalcifer.Engine.NodeRegistry`); the editor palette (`frontend/src/pages/editor/nodeTypes.ts`)
> must carry the same 31 keys.

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
│   ├── frequency_cap               # ✅ Skip if customer exceeded message limit
│   ├── check_segment               # ✅ Branch based on segment membership
│   └── preference_gate             # ✅ Branch based on customer preferences
│
├── action/channel
│   ├── send_email                  # ✅ Send email via provider
│   ├── send_sms                    # ✅ Send SMS via provider
│   ├── send_push                   # ✅ Send push notification via provider
│   ├── send_whatsapp               # ✅ Send WhatsApp message via provider
│   ├── send_in_app                 # ✅ Send in-app message via provider
│   └── call_webhook                # ✅ HTTP call to external service
│
├── action/data
│   ├── update_profile              # ✅ Update customer profile fields
│   ├── add_tag                     # ✅ Add tags to customer
│   ├── custom_code                 # ✅ Execute custom Elixir expression
│   ├── track_conversion            # ✅ Record conversion event
│   └── memory_recall               # ✅ Recall stored tenant memory into context
│
├── action/ai
│   ├── ai_think                    # ✅ AI generates text/analysis from flow context
│   ├── ai_decide                   # ✅ AI-powered branching (category :condition)
│   ├── ai_notify                   # ✅ AI-summarized operator notifications (PubSub)
│   ├── agent                       # ✅ Autonomous AI agent step (tool-using, multi-round)
│   └── flow_router                 # ✅ AI routes to a downstream branch (category :condition)
│
├── orchestration                   # (lives directly under nodes/action/)
│   ├── parallel_group              # ✅ Run child tasks concurrently, join results
│   └── sub_flow                    # ✅ Invoke another flow (optionally wait for it)
│
├── wait
│   ├── wait                        # ✅ Delay for duration (e.g. "3d", "2h")
│   ├── wait_until                  # ✅ Wait until specific datetime
│   └── wait_for_event              # ✅ Pause until matching event arrives
│
└── end
    ├── exit                        # ✅ Normal flow termination
    └── goal_reached                # ✅ Flow completed with goal conversion
```

---

## Scope Reference

> commit format: `type(scope/subscope): description`

| scope | subscopes |
|-------|-----------|
| `engine` | `executor`, `nodes`, `events`, `recovery`, `persistence`, `jobs`, `errors`, `circuit-breaker`, `observability` |
| `flows` | `lifecycle`, `versions`, `graph`, `instances` |
| `channels` | `providers`, `delivery`, `webhooks` |
| `customers` | `profiles`, `segments` |
| `analytics` | `stats`, `funnel`, `conversions` |
| `marketing` | `journeys` |
| `tenants` | `auth` |
| `accounts` | `users`, `oauth` |
| `audit` | `log` |
| `api` | `flows`, `versions`, `instances`, `triggers`, `customers`, `segments`, `analytics`, `journeys`, `chat`, `conversations`, `settings`, `deliveries`, `audit`, `auth`, `webhooks`, `simulation`, `engine`, `tenants`, `health`, `middleware` |
| `ws` | `monitoring`, `presence` |
| `ai` | `chat`, `providers`, `tools`, `context`, `agents`, `prompts` |
| `simulators` | `email`, `sms`, `push`, `whatsapp`, `in-app` |
| `fe` | `shell`, `auth`, `design`, `chat`, `work`, `editor`, `engine-room`, `browse` |
| `infra` | `docker`, `ci`, `release` |

Note: `instances` is a **`flows`** subscope (and an `api` one) — never `engine/instances`.
Always commit with a subscope; bare `feat(ai): ...` has slipped in before.

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
