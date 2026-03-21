# Kalcifer — Master Plan

**Version**: 2.0
**Date**: 2026-03-21
**Status**: Active
**License**: Apache 2.0 (Core) + Proprietary (Cloud/Enterprise)

> ეს დოკუმენტი არის **ერთადერთი source of truth** Kalcifer-ის ბიზნეს ხედვის, ტექნიკური არქიტექტურის და განვითარების გეგმისთვის. ყველა სხვა დოკუმენტი (01-BRD, 02-ARCHITECTURE, etc.) ამ დოკუმენტს ემორჩილება.

---

## სარჩევი

1. [ხედვა და მისია](#1-ხედვა-და-მისია)
2. [აქტუალური მდგომარეობა](#2-აქტუალური-მდგომარეობა)
3. [ბიზნეს მოდელი](#3-ბიზნეს-მოდელი)
4. [განვითარების გეგმა](#4-განვითარების-გეგმა)
5. [ტექნიკური არქიტექტურა](#5-ტექნიკური-არქიტექტურა)
6. [Go-to-Market სტრატეგია](#6-go-to-market-სტრატეგია)
7. [ფინანსური გეგმა](#7-ფინანსური-გეგმა)
8. [რისკები და მითიგაცია](#8-რისკები-და-მითიგაცია)
9. [წარმატების მეტრიკები](#9-წარმატების-მეტრიკები)
10. [დოკუმენტაციის ინდექსი](#10-დოკუმენტაციის-ინდექსი)

---

## 1. ხედვა და მისია

### მისია

Kalcifer არის open-source flow orchestration engine, რომელიც AI-ის საშუალებით ბიზნეს პროცესებს ავტომატიზებს. ჩვენი მთავარი მიზანი — **AI სერვისების გადაყიდვა** managed platform-ის სახით, სადაც flow engine არის საფუძველი და AI არის revenue center.

### Core Thesis

Marketing Automation ბაზარი ($15B+) დომინირებულია ძვირიან, დახურულ SaaS პლატფორმებით (Braze $50K+/წელი, Customer.io, Klaviyo). არ არსებობს production-grade, open-source, AI-first visual journey builder. Kalcifer ავსებს ამ ნიშას ტექნიკურად უპირატესი execution engine-ით.

### რატომ Kalcifer?

| კონკურენტი | პრობლემა | Kalcifer-ის უპირატესობა |
|-----------|----------|----------------------|
| Braze/Iterable | $50K+/წელი, vendor lock-in | Open-source, self-hosted, 10-50x იაფი |
| N8N/Zapier | Generic, არა customer journey-ისთვის | Purpose-built, WaitForEvent, A/B testing |
| Customer.io | No live versioning, limited AI | Live migration, AI-first design |
| Temporal | Developer-only, no UI | Visual editor + AI copilot |

### Key Differentiators

1. **AI-First Design** — NL → Flow graph, Document → Flow, AI optimization, Smart debugging
2. **Live Journey Versioning** — 50,000 active customer-ით journey-ის update mid-flight
3. **BEAM Fault Tolerance** — Per-instance process isolation, zero cascade failures
4. **WaitForEvent Pattern** — Native event-driven pause/resume
5. **Open-Core Model** — სრული engine უფასოდ, AI + Cloud ფასიანი

---

## 2. აქტუალური მდგომარეობა

> ბოლო განახლება: 2026-03-21

### რა არის აშენებული (Phase 0 — დასრულებული)

| კომპონენტი | სტატუსი | დეტალები |
|-----------|---------|----------|
| Execution Engine | ✅ Done | FlowServer GenServer/instance, DynamicSupervisor, Registry |
| Node System | ✅ Done | 24 node type (3 trigger, 5 condition, 3 wait, 6 channel, 4 data, 3 end) |
| Live Migration | ✅ Done | NodeMapper, Migrator, rollback, new-entries-only strategy |
| REST API | ✅ Done | 40+ endpoints, Bearer token auth, rate limiting |
| WebSocket | ✅ Done | Flow monitoring channels |
| Recovery | ✅ Done | RecoveryManager restores waiting instances on boot |
| Multi-tenancy | ✅ Done | API key → tenant isolation |
| Docker | ✅ Done | Multi-stage Dockerfile, docker-compose (PG + ES + CH) |
| CI | ✅ Done | GitHub Actions (test, lint, Claude code review) |
| Tests | ✅ Done | 407+ tests, 7 properties, 14 bug regression tests, 2 integration tests |
| Documentation | ✅ Done | BRD, Architecture, Tech Specs, Testing, Deployment, Monetisation docs |

### რა არის Stub/Placeholder

| კომპონენტი | სტატუსი | რა სჭირდება |
|-----------|---------|------------|
| Channel Providers | ⚠️ Stub | მხოლოდ LogProvider + WebhookProvider; SendGrid, Twilio არ არის |
| Analytics | ⚠️ Stub | Collector არის, ClickHouse pipeline არა |
| Customer Model | ⚠️ Partial | Schema არის, SegmentEvaluator partial |
| Auth (Guardian/JWT) | ⚠️ Imported | Guardian imported, not configured |
| Broadway Pipeline | ⚠️ Imported | Imported, not used |
| AI Designer | ❌ None | არ არსებობს, მაგრამ არის ძირითადი revenue source |
| Frontend UI | ⚠️ Prototype | 3 HTML prototype (main, engine-room, browse), React app არა |
| Sandbox (CustomCode) | ❌ None | Lua runner not implemented |
| Elasticsearch Integration | ❌ None | In docker-compose, not connected |
| ClickHouse Integration | ❌ None | In docker-compose, not connected |

### ცნობილი ბაგები (8)

| კოდი | ბაგი | სიმძიმე |
|------|------|---------|
| C1 | Cross-tenant event injection | **Critical/Security** |
| C3 | ResumeFlowJob dead process → `:ok` | Critical |
| C6/I13 | wait_until migration atom mismatch | Critical |
| C9 | nil customer_id bypasses dedup | High |
| I1 | FlowInstance no state machine | High |
| I5 | Invalid migration strategy → 500 | Medium |
| T5 | Same-version migration → 500 | Medium |
| N4 | AbSplit empty variants → crash | Medium |

### ტექნიკური ფაქტები

| Metric | Value |
|--------|-------|
| Elixir | ~> 1.18, OTP 28 |
| PostgreSQL | 16+ |
| Source files (lib/) | 97 |
| Test files | 65 |
| Node types | 24 |
| API endpoints | 40+ |
| DB migrations | 14 |
| Dependencies | 33 |

---

## 3. ბიზნეს მოდელი

### Open-Core Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Community Edition                        │
│                  Apache 2.0 — უფასო                      │
│                                                          │
│  24 node engine │ REST + WebSocket API │ Live Migration   │
│  Visual Editor  │ Docker Compose deploy │ Plugin SDK      │
│  AI Designer (BYOK — Bring Your Own Key)                 │
│                                                          │
│  ────── ეს არ არის crippled ვერსია ──────               │
│  ────── ეს არის სრული production პროდუქტი ──────        │
└─────────────────────────────────────────────────────────┘
          │                          │
          ▼                          ▼
┌───────────────────┐    ┌──────────────────────────┐
│  Kalcifer Cloud   │    │  Enterprise Edition      │
│  (Managed SaaS)    │    │  (Self-hosted, licensed) │
│                    │    │                          │
│  Zero-ops hosting  │    │  Multi-tenancy           │
│  Managed AI        │    │  SSO (SAML/OIDC)         │
│  Auto-scaling      │    │  Audit log + RBAC        │
│  SOC2 compliance   │    │  Dedicated support       │
│  99.9% SLA         │    │  White-label             │
│                    │    │                          │
│  $299-2,999/mo     │    │  $999-9,999/mo           │
└───────────────────┘    └──────────────────────────┘
```

### Revenue Streams

| Stream | Model | Margin | მოცულობა (12 თვე) |
|--------|-------|--------|-------------------|
| Cloud SaaS | Subscription + AI usage | ~80% | $35K MRR |
| Enterprise | License + Support | ~88% | $20K MRR |
| AI Conversations | Per-conversation overage | ~70-90% | $5K MRR |
| Professional Services | Implementation, Training | ~60% | $10K one-time |
| **ჯამი** | | | **$55K+ MRR** |

### Pricing Tiers

| Plan | ფასი | AI Conversations | Target |
|------|------|-----------------|--------|
| Community | $0 | BYOK (own API key) | Developers, startups |
| Cloud Starter | $299/mo | 1,000/mo included | Series A/B, 10-100K customers |
| Cloud Growth | $999/mo | 5,000/mo included | Mid-market, 100K-1M customers |
| Cloud Scale | $2,999/mo | Unlimited | Large companies, 1M+ customers |
| Enterprise | $999-9,999/mo | Custom | Data sovereignty needs |

**AI Unit Economics:**
- Avg LLM cost/conversation: ~$0.03 (Claude Haiku/Sonnet mix)
- Revenue/conversation: $0.10-0.30
- AI Gross Margin: 70-90%

---

## 4. განვითარების გეგმა

### ფაზების მიმოხილვა

```
Phase 0  ✅ DONE     Engine Core (6 კვირა)
Phase 1  📍 CURRENT  Production Readiness (8 კვირა)
Phase 2  ⬜ NEXT     Open-Source Launch + AI UI (8 კვირა)
Phase 3  ⬜ FUTURE   Cloud Launch (6 კვირა)
Phase 4  ⬜ FUTURE   Scale & Ecosystem (ongoing)
```

---

### Phase 1: Production Readiness (კვირა 1–8)

**მიზანი**: Engine-ის production-ready გახდომა, ბაგ ფიქსები, რეალური პროვაიდერები

#### Sprint 1 (კვირა 1–2): Bug Fixes & Input Validation

**დეტალური ინსტრუქციები**: → `PHASE-1.md`, Increment 12

| ამოცანა | ფაილები | ტესტები |
|---------|---------|---------|
| C1: Cross-tenant event fix | event_router.ex, instance_store.ex | cross_tenant_event_test |
| C3: ResumeFlowJob snooze | resume_flow_job.ex | resume_job_dead_process_test |
| C6: wait_until migration | node_mapper.ex, flow_server.ex | wait_until_migration_test |
| C9: nil customer_id | trigger_controller.ex, event_controller.ex | nil_customer_id_test |
| I1: Status state machine | flow_instance.ex | instance_status_transition_test |
| I5: Invalid strategy | migration_controller.ex | invalid_migration_strategy_test |
| T5: Same version | fallback_controller.ex | same_version_migration_test |
| N4: AbSplit empty | ab_split.ex | ab_split_empty_variants_test |
| API validation | All controllers | New validation tests |

**Definition of Done**: 0 `@tag :known_bug`, 0 failures, `mix precommit` passes

#### Sprint 2 (კვირა 3–4): Channel Provider Architecture

**დეტალური ინსტრუქციები**: → `PHASE-1.md`, Increment 13

| ამოცანა | დეტალი |
|---------|--------|
| Provider Behaviour | `send_message/4`, `delivery_status/1` callbacks |
| SendGrid Provider | Email — SendGrid API v3 integration |
| Twilio Provider | SMS + WhatsApp — Twilio REST API |
| Delivery Tracking | Schema: pending → sent → delivered → bounced → failed |
| Inbound Webhooks | `/webhooks/sendgrid`, `/webhooks/twilio` — signature verification |
| Send Message Job | Oban worker, async delivery, retry with backoff |

**New files**: ~12  **New tests**: ~36  **Migrations**: 1

#### Sprint 3 (კვირა 5–6): Customer Data & Analytics

**დეტალური ინსტრუქციები**: → `PHASE-1.md`, Increments 14-15

| ამოცანა | დეტალი |
|---------|--------|
| Customer CRUD | Full CRUD, upsert by external_id, tags, preferences |
| Segment Engine | Rule evaluator (eq, neq, gt, lt, contains, in) |
| Context Enrichment | Customer data injected into flow context |
| Analytics Collection | Telemetry → batched stats (GenServer flush) |
| Analytics API | Summary, node breakdown, funnel, A/B results |
| Conversion Tracking | Goal reached → conversion record |

**New files**: ~20  **New tests**: ~63  **Migrations**: 3

#### Sprint 4 (კვირა 7–8): Real-time & Production Hardening

**დეტალური ინსტრუქციები**: → `PHASE-1.md`, Increments 16-17

| ამოცანა | დეტალი |
|---------|--------|
| PubSub Broadcasting | instance_started/completed/failed, node_executed events |
| WebSocket Channels | flow:{id}, tenant:{id} subscriptions |
| Instance Inspector | List, detail, timeline, cancel APIs |
| Rate Limiting | Token bucket/tenant (ETS), 429 + Retry-After |
| Structured Logging | JSON logging, correlation IDs |
| Circuit Breaker | Provider failure threshold → circuit open |
| Oban Maintenance | Cleanup (stale instances), Stats rollup (daily) |

**New files**: ~18  **New tests**: ~48  **Migrations**: 0

#### Phase 1 Summary

| Metric | Phase 0 | Phase 1 End |
|--------|---------|-------------|
| Tests | 407 | ~554 |
| Known bugs | 8 | 0 |
| Channel providers | 1 (log) | 4 (log, webhook, sendgrid, twilio) |
| Analytics | Stub | PostgreSQL-based, full API |
| Customer model | Partial | Full CRUD + segments |
| Real-time | Basic | PubSub + WebSocket channels |

---

### Phase 2: Open-Source Launch + AI-Enabled UI (კვირა 9–16)

**მიზანი**: GitHub release, React UI, AI Copilot — **ეს ფაზა არის turning point**

#### Sprint 5 (კვირა 9–10): Repository & Open-Source Preparation

| ამოცანა | დეტალი |
|---------|--------|
| License | `LICENSE` (Apache 2.0), `LICENSE-ENTERPRISE` (Proprietary) |
| Repo Structure | CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md, CHANGELOG.md |
| CI/CD | ci.yml (test+lint+dialyzer), docker-publish.yml (ghcr.io), release.yml |
| Docker Simplification | `docker compose up` = working system in 2 minutes |
| .env.example | All env vars documented |
| Makefile | setup, dev, test, lint, ci, deploy, docker-* targets |
| README Rewrite | Hero section, demo GIF, quick start, architecture overview |
| Issue/PR Templates | Bug report, feature request, PR template |

**არსებული ფაილები** (უკვე შექმნილი ამ სესიაში):
- ✅ `fly.toml`
- ✅ `Makefile`
- ✅ `.env.example`
- ✅ `CONTRIBUTING.md`
- ✅ `SECURITY.md`
- ✅ `.github/workflows/ci.yml`
- ✅ `.github/workflows/docker-publish.yml`

#### Sprint 6 (კვირა 11–12): Documentation Site

| ამოცანა | დეტალი |
|---------|--------|
| Doc Framework | MkDocs Material ან ExDoc — deploy to docs.kalcifer.dev |
| Getting Started | 5-minute quickstart (Docker + cURL) |
| API Reference | OpenAPI 3.1 spec, Swagger/Redoc UI |
| Architecture Guide | Simplified version of 02-ARCHITECTURE.md |
| Node Development | Plugin SDK guide — build your own nodes |
| Deployment Guide | Docker, Fly.io, Kubernetes |
| Concepts | Flow, Instance, Version, Migration explained |

#### Sprint 7 (კვირა 13–14): React Frontend + Visual Editor

| ამოცანა | Tech | დეტალი |
|---------|------|--------|
| Project Setup | React 19, Vite, TypeScript, Tailwind | `ui/` directory, monorepo structure |
| Flow Editor | ReactFlow | Visual canvas, drag-drop nodes, edge connections |
| Node Renderers | React components | TriggerNode, ActionNode, ConditionNode, WaitNode, EndNode |
| Node Config Panel | Shadcn/UI forms | Properties editor per node type |
| API Client | Fetch + Zustand | REST client, WebSocket hooks |
| Dashboard | Recharts | Flow list, instance counts, quick stats |
| Real-time Monitor | WebSocket | Live instance tracking, node execution animation |

**Frontend Stack**:
```
ui/
├── src/
│   ├── components/flow-editor/    # ReactFlow canvas
│   ├── components/ai-copilot/     # AI chat sidebar
│   ├── components/dashboard/      # Overview
│   ├── components/analytics/      # Charts
│   ├── api/                       # REST + WS client
│   ├── hooks/                     # useFlow, useWebSocket, useAI
│   ├── stores/                    # Zustand state
│   └── types/                     # TypeScript types
```

**პროტოტიპიდან production-ზე**:
- `main.html` → Dashboard + Flow list
- `engine-room.html` → Flow Editor (ReactFlow)
- `browse.html` → Node browser + AI Copilot panel

#### Sprint 8 (კვირა 15–16): AI Service Layer + v0.1.0 Release

**ეს sprint არის revenue center-ის საფუძველი.**

| ამოცანა | დეტალი |
|---------|--------|
| LLM Router | Multi-provider: Claude, OpenAI, Gemini, Ollama (self-hosted) |
| Flow Generation | NL → validated flow graph JSON |
| Document → Flow | Excel/CSV/Word upload → parsed intent → flow graph |
| Flow Explanation | Existing flow → NL description |
| AI Optimization | Analytics data → improvement suggestions |
| Smart Debugging | Instance error → root cause analysis |
| BYOK Mode | Community: own API key, managed: included in plan |

**AI Architecture**:

```elixir
# lib/kalcifer/ai/ (Community — BYOK)
├── llm_provider.ex          # Behaviour: chat/2, stream/2
├── providers/
│   ├── anthropic.ex         # Claude API
│   ├── openai.ex            # GPT-4 API
│   ├── gemini.ex            # Gemini API
│   └── ollama.ex            # Self-hosted
├── prompt_builder.ex        # System prompt + node catalog + few-shot
├── graph_generator.ex       # LLM response → validated graph
├── document_parser.ex       # File → structured intent
└── conversation.ex          # Multi-turn state

# lib/kalcifer_cloud/ai/ (Proprietary — managed)
├── llm_router.ex            # Smart routing, cost optimization
├── usage_tracker.ex         # Per-tenant conversation counting
├── suggestion_engine.ex     # Analytics-based optimization
└── auto_segmentation.ex     # Customer data → auto-segments
```

**AI API Endpoints**:

```
POST /api/v1/ai/generate-flow        # NL → Flow graph
POST /api/v1/ai/document-to-flow     # Document upload → Flow
POST /api/v1/ai/explain              # Flow → NL description
POST /api/v1/ai/optimize             # Flow → suggestions
POST /api/v1/ai/debug                # Instance error → root cause
POST /api/v1/ai/conversations        # Multi-turn conversation
POST /api/v1/ai/conversations/:id    # Continue conversation
```

**v0.1.0 Release Checklist**:
- [ ] Engine: 24 nodes, 0 bugs, full API
- [ ] Providers: SendGrid, Twilio, Webhook
- [ ] UI: React flow editor + AI copilot
- [ ] AI: Flow generation, explanation, BYOK
- [ ] Docker: `docker compose up` → working system
- [ ] Docs: Getting started, API reference, node development guide
- [ ] GitHub Release: binary + Docker image (ghcr.io)
- [ ] CHANGELOG.md: v0.1.0

---

### Phase 3: Cloud Launch on Fly.io (კვირა 17–22)

**მიზანი**: ფასიანი Cloud ვერსიის გაშვება, პირველი revenue

#### Sprint 9 (კვირა 17–18): Fly.io Infrastructure

| ამოცანა | დეტალი |
|---------|--------|
| Fly.io Setup | App + Postgres in Frankfurt (fra) region |
| BEAM Clustering | libcluster + DNS polling on Fly.io internal network |
| Secrets Management | fly secrets: DB, API keys, Stripe |
| SSL/Domain | app.kalcifer.dev → Fly.io, docs.kalcifer.dev → Cloudflare |
| Monitoring | Grafana Cloud (free), Sentry, structured JSON logs |
| Zero-downtime Deploy | Rolling strategy, health checks, min 2 machines |

**fly.toml** — ✅ უკვე შექმნილი

**Clustering Config**:
```elixir
config :libcluster,
  topologies: [
    fly6pn: [
      strategy: Cluster.Strategy.DNSPoll,
      config: [
        polling_interval: 5_000,
        query: "kalcifer.internal",
        node_basename: "kalcifer"
      ]
    ]
  ]
```

#### Sprint 10 (კვირა 19–20): Multi-Tenancy & Billing

| ამოცანა | დეტალი |
|---------|--------|
| Cloud Tenant Schema | Plan, Stripe IDs, AI usage counters, feature flags |
| Stripe Integration | Subscriptions, customer portal, webhook handler |
| Usage Metering | AI conversation counting → Stripe metered billing |
| Plan Enforcement | Feature gates, rate limits per plan |
| Onboarding Flow | Sign up → create workspace → first flow |

**Billing Endpoints**:
```
POST /api/v1/billing/subscribe       # Create subscription
POST /api/v1/billing/portal          # Stripe customer portal
GET  /api/v1/billing/usage           # Current usage
POST /webhooks/stripe                # Stripe webhook
```

#### Sprint 11 (კვირა 21–22): Landing Page & Launch

| ამოცანა | დეტალი |
|---------|--------|
| Landing Page | kalcifer.dev — static site, Cloudflare Pages |
| Demo Instance | demo.kalcifer.dev — read-only, pre-loaded flows |
| Status Page | status.kalcifer.dev — BetterStack |
| Launch Campaign | HN, Product Hunt, Elixir Forum, Reddit |
| v1.0.0 Release | Cloud GA |

---

### Phase 4: Scale & Ecosystem (კვირა 23+)

| ამოცანა | Timeline | დეტალი |
|---------|----------|--------|
| SDK/Client Libraries | Month 7-8 | Python, JavaScript, Go clients |
| Plugin Marketplace | Month 9-10 | Community nodes, 20% commission |
| Enterprise Features | Month 8-12 | SSO/SAML, audit log, RBAC, white-label |
| ClickHouse Analytics | Month 10-12 | Advanced analytics pipeline (Broadway → CH) |
| Elasticsearch Segments | Month 10-12 | Real-time segment evaluation |
| GraphQL API | Month 12+ | Alternative to REST |
| Mobile SDKs | Month 12+ | iOS/Android push integration |
| Internationalization | Month 12+ | i18n support |

---

## 5. ტექნიკური არქიტექტურა

### სისტემის დიაგრამა (სამიზნე — Phase 3 დასრულების შემდეგ)

```
┌──────────────────────────────────────────────────────────────┐
│                      Kalcifer System                          │
│                                                              │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐  │
│  │  Phoenix API  │ │  Flow Engine │ │  AI Service Layer    │  │
│  │  (REST + WS)  │ │  (OTP/BEAM)  │ │  (LLM Router)        │  │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────────────┘  │
│         │               │               │                    │
│  ┌──────┴───────────────┴───────────────┴────────────────┐   │
│  │                Core Domain Services                    │   │
│  │  Flows │ Customers │ Channels │ Versioning │ Analytics │   │
│  └───────────────────────┬───────────────────────────────┘   │
│                           │                                  │
│  ┌────────────────────────┴──────────────────────────────┐   │
│  │               Infrastructure Layer                     │   │
│  │  Ecto (PG) │ Oban (Jobs) │ PubSub │ LLM APIs │ Stripe │   │
│  └────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
         │              │              │
    PostgreSQL 16    LLM Provider    Stripe
                   (Claude/OpenAI/
                    Gemini/Ollama)
```

### Engine Architecture

```
Kalcifer.Engine.Supervisor (rest_for_one)
├── Registry (ProcessRegistry)          # Process name lookup
├── NodeRegistry (ETS)                  # type_string → module mapping
├── ProviderRegistry (ETS)              # channel → provider mapping
├── Analytics.Collector (GenServer)     # Batched stats collection
├── CircuitBreaker (GenServer)          # Provider failure detection
├── FlowSupervisor (DynamicSupervisor) # Per-instance GenServers
│   ├── FlowServer (instance_1)
│   ├── FlowServer (instance_2)
│   └── FlowServer (instance_N)
└── RecoveryManager (GenServer)         # Boot-time crash recovery
```

### Node System (24 built-in)

| Category | Nodes | Count |
|----------|-------|-------|
| Trigger | event_entry, segment_entry, webhook_entry | 3 |
| Condition | condition, ab_split, frequency_cap, check_segment, preference_gate | 5 |
| Wait | wait, wait_until, wait_for_event | 3 |
| Action/Channel | send_email, send_sms, send_push, send_whatsapp, send_in_app, call_webhook | 6 |
| Action/Data | update_profile, add_tag, custom_code, track_conversion | 4 |
| End | exit, goal_reached | 2 |
| **Total** | | **24** (*არა 20, როგორც BRD-ში წერია — განახლებულია*) |

### Tech Stack (აქტუალური)

| Component | Technology | Version |
|-----------|-----------|---------|
| Language | Elixir | ~> 1.18 |
| Runtime | Erlang/OTP | 28 |
| Web Framework | Phoenix | ~> 1.7 |
| Database ORM | Ecto | ~> 3.12 |
| Job Queue | Oban | ~> 2.18 |
| HTTP Server | Bandit | ~> 1.5 |
| HTTP Client | Req + Finch | ~> 0.5 / ~> 0.19 |
| Auth | Guardian | ~> 2.3 |
| Encryption | Cloak.Ecto | ~> 1.3 |
| Clustering | libcluster | ~> 3.3 |
| Frontend | React 19 + ReactFlow + TypeScript | (Phase 2) |
| Primary DB | PostgreSQL | 16+ |
| Analytics DB | ClickHouse | 24.x (Phase 4) |
| Search | Elasticsearch | 8.x (Phase 4) |

> **შენიშვნა**: ES და ClickHouse Phase 4-ში შედის. Phase 1-3-ში analytics მხოლოდ PostgreSQL-ზეა.

### Infrastructure Map

```
kalcifer.dev                      # Landing page (Cloudflare Pages)
├── app.kalcifer.dev              # Cloud UI (React, Fly.io)
├── api.kalcifer.dev              # API (Phoenix, Fly.io — same app)
├── docs.kalcifer.dev             # Documentation (MkDocs, Cloudflare)
├── demo.kalcifer.dev             # Demo instance (Fly.io, read-only)
└── status.kalcifer.dev           # Status page (BetterStack)

github.com/kalcifer/kalcifer      # Main repo (Apache 2.0)
github.com/kalcifer/kalcifer-ui   # Frontend repo (Apache 2.0)
ghcr.io/kalcifer/kalcifer         # Docker images
```

---

## 6. Go-to-Market სტრატეგია

### Phase 1: Community Building (Month 0-4)

**მიზანი**: 5,000 GitHub stars, 100 Discord members

| Channel | Action | Expected Impact |
|---------|--------|-----------------|
| Hacker News | "Show HN: Open-source AI-powered customer journey builder on Elixir/OTP" | 2-5K visitors, 200+ stars |
| Elixir Forum | Architecture posts, ElixirConf talk proposal | Community credibility |
| Reddit | r/elixir, r/selfhosted, r/marketing | Early adopters |
| Dev.to/Hashnode | Technical blog series | SEO, thought leadership |
| Discord | Community server | Direct feedback loop |

**Content Ideas**:
- "Why your customer journey engine shouldn't be built on Node.js"
- "WaitForEvent: The pattern that N8N can't do"
- "How we publish reliability reports with every release"
- "Building a fault-tolerant workflow engine with OTP"
- "AI-first journey design: NL to production flow in 30 seconds"

### Phase 2: Cloud Launch (Month 4-8)

**მიზანი**: 25 paying Cloud customers, $15K MRR

| Channel | Action |
|---------|--------|
| Product Hunt | "Open-source Braze alternative with AI" |
| In-app conversion | Self-hosted → Cloud banner |
| Partnerships | SendGrid, Twilio blog features |
| Case studies | Early adopter success stories |
| YouTube | Demo video: "Build a journey in 30 seconds with AI" |

### Phase 3: Enterprise (Month 8-12)

**მიზანი**: 5 Enterprise customers, $55K total MRR

| Channel | Action |
|---------|--------|
| Direct outreach | Companies using self-hosted at scale |
| Partner channel | Implementation consultancies |
| Conferences | SaaStr, MarTech presence |

---

## 7. ფინანსური გეგმა

### Revenue Projections (24 months)

| Month | Stars | Cloud Customers | Enterprise | Cloud MRR | Enterprise MRR | AI Revenue | Total MRR |
|-------|-------|-----------------|------------|-----------|----------------|------------|-----------|
| 0 | 500 | 0 | 0 | $0 | $0 | $0 | $0 |
| 4 | 3,000 | 0 | 0 | $0 | $0 | $0 | $0 |
| 6 | 5,000 | 10 | 0 | $4K | $0 | $1K | $5K |
| 9 | 8,000 | 25 | 2 | $12K | $4K | $5K | $21K |
| 12 | 12,000 | 50 | 5 | $25K | $15K | $15K | $55K |
| 18 | 20,000 | 100 | 10 | $55K | $35K | $35K | $125K |
| 24 | 30,000 | 180 | 18 | $100K | $60K | $80K | $240K |

> **AI Revenue** ცალკეა გამოყოფილი, რადგან ეს არის ჩვენი ძირითადი growth lever.

### Unit Economics

| Metric | Cloud Starter | Cloud Growth | Cloud Scale | Enterprise |
|--------|---------------|--------------|-------------|------------|
| Price | $299/mo | $999/mo | $2,999/mo | $2,500/mo avg |
| COGS (infra) | $50 | $150 | $500 | $0 |
| Gross Margin | 83% | 85% | 83% | 100% |
| LTV (24mo) | $5,500 | $19,200 | $57,600 | $52,800 |
| CAC target | $500 | $2,000 | $5,000 | $5,000 |
| LTV:CAC | 11:1 | 9.6:1 | 11.5:1 | 10.6:1 |

### Operational Budget (Pre-revenue)

| Category | Monthly | Notes |
|----------|---------|-------|
| Fly.io (app + DB) | $50-150 | Performance VMs, Postgres |
| Domain | $1 | kalcifer.dev |
| Cloudflare Pages | $0 | Landing + docs |
| Claude API (dev) | $100-500 | AI feature development |
| SendGrid | $0 | Free tier (100/day) |
| Twilio | Pay-per-use | SMS testing |
| **Total** | **$200-700/mo** | |

### Funding Strategy

| Phase | Timing | Amount | Signal |
|-------|--------|--------|--------|
| Bootstrap | Month 0-6 | $50-100K (self/angel) | Build core, achieve 5K stars |
| Seed | Month 6-12 | $500K-1M | 10K+ stars, 25+ customers, $15K MRR |
| Series A | Month 18-24 | $3-5M | 30K+ stars, 150+ customers, $150K MRR |

---

## 8. რისკები და მითიგაცია

| # | რისკი | Impact | Likelihood | მითიგაცია |
|---|-------|--------|------------|-----------|
| 1 | AI cost spikes (LLM pricing) | High | Medium | Multi-provider router, Ollama self-hosted fallback, caching |
| 2 | Elixir hiring difficulty | High | Medium | Strong docs, contributor-friendly, Elixir community engagement |
| 3 | AWS/GCP competitive service | High | Low | Community moat, faster iteration, open-source lock-in impossible |
| 4 | Visual editor complexity | High | Medium | ReactFlow foundation, phased delivery |
| 5 | Self-hosted never converts | Medium | Medium | Enterprise features (SSO, audit) create separate revenue |
| 6 | Adoption requires integrations | Medium | High | Webhook covers 80%, Plugin SDK for custom nodes |
| 7 | Competitor open-sources similar | Medium | Low | First-mover + reliability reputation = moat |
| 8 | Open-source maintenance burden | Medium | Medium | Sustainable community, prioritize paid features |
| 9 | Security vulnerability in engine | High | Low | Security policy, responsible disclosure, regular audits |
| 10 | LLM quality degrades | Medium | Low | Multi-provider, prompt engineering, validation layer |

---

## 9. წარმატების მეტრიკები

### 6-თვიანი (v0.1.0 release + Cloud beta)

| Metric | Target |
|--------|--------|
| GitHub Stars | 5,000 |
| Docker pulls | 10,000 |
| Weekly active self-hosted | 100 |
| Cloud beta users | 25 |
| MRR | $5,000 |
| Discord members | 500 |
| Contributors | 10 |
| AI conversations/month | 5,000 |
| Test count | 600+ |
| Uptime | 99.5% |

### 12-თვიანი (v1.0.0 GA)

| Metric | Target |
|--------|--------|
| GitHub Stars | 12,000 |
| Docker pulls | 50,000 |
| Weekly active self-hosted | 500 |
| Cloud customers (paying) | 50 |
| Enterprise customers | 5 |
| MRR | $55,000 |
| ARR | $660,000 |
| NRR (Net Revenue Retention) | >120% |
| Contributors | 50 |
| Community nodes (marketplace) | 20 |
| Uptime | 99.9% |

### Engineering Quality (per release)

| Metric | Target |
|--------|--------|
| Test count | >600 |
| Property-based scenarios | >500 |
| Zero known_bug tests | Yes |
| `mix precommit` passing | Yes |
| Dialyzer clean | Yes |
| Load test: concurrent flows | >100K |
| Mean recovery time | <5 seconds |

---

## 10. დოკუმენტაციის ინდექსი

### აქტიური დოკუმენტები

| ფაილი | შინაარსი | სტატუსი |
|-------|----------|---------|
| `00-MASTER-PLAN.md` | **ეს დოკუმენტი** — ერთიანი source of truth | ✅ Active |
| `PHASE-1.md` | Phase 1 დეტალური implementation plan (Increments 12-17) | ✅ Active — reference for current work |

### საცნობარო დოკუმენტები (Phase 0 პერიოდის)

> ეს დოკუმენტები Phase 0-ის პერიოდში დაიწერა (2026-02-22). ზოგიერთი დეტალი მოძველებულია. საჭირო ინფორმაციისთვის ჯერ ეს Master Plan უნდა შეამოწმოთ.

| ფაილი | შინაარსი | ცნობილი განსხვავებები Master Plan-თან |
|-------|----------|-------------------------------------|
| `01-BRD.md` | ბიზნეს მოთხოვნები, user stories, competitive analysis | Node count: ამბობს 20, რეალურად 24. Elixir version: 1.17 → 1.18 |
| `02-ARCHITECTURE.md` | სისტემის არქიტექტურა, process model, AI designer spec | AI Designer spec არის aspirational — ჯერ არ არის implemented |
| `03-TECH-SPECS.md` | API spec, data models, frontend spec | Elixir 1.17/OTP 27 → 1.18/OTP 28. Frontend spec aspirational |
| `04-TESTING-STRATEGY.md` | Testing pyramid, property/chaos/load test plans | Chaos/load tests ჯერ არ არის implemented |
| `05-DEPLOYMENT.md` | Docker, K8s, standalone deployment | SQLite tier არ არის implemented. K8s manifests aspirational |
| `06-MONETISATION.md` | Pricing, revenue projections, funding strategy | Pricing accurate. Revenue projections conservative — AI revenue not separated |

### განახლების საჭიროებები

| დოკუმენტი | Action | Priority |
|-----------|--------|----------|
| `01-BRD.md` | Update node count (20→24), Elixir version, add AI revenue focus | P2 |
| `02-ARCHITECTURE.md` | Mark AI Designer as "Phase 2", update file paths | P2 |
| `03-TECH-SPECS.md` | Update versions, mark frontend as "Phase 2" | P2 |
| `README.md` | Complete rewrite for open-source launch | **P1** (Sprint 5) |
| `CLAUDE.md` | Keep as-is, update during implementation | P3 |

---

## Appendix A: Glossary Updates

| Term | Definition | შენიშვნა |
|------|-----------|----------|
| **Flow** | Core engine ტერმინი — DAG graph რომელიც პროცესს აღწერს | არა "Journey" — Journey არის marketing wrapper |
| **Journey** | Marketing wrapper Flow-ზე — customer engagement ფოკუსით | `Kalcifer.Marketing.Journey` schema |
| **Node** | Graph-ის ერთი ნაბიჯი (action, condition, wait, etc.) | 24 built-in, extensible via Plugin SDK |
| **Instance** | Flow-ის ერთი execution customer-ისთვის | GenServer per instance |
| **Version** | Flow graph-ის immutable snapshot | v1, v2, v3... |
| **Migration** | Active instance-ების გადატანა ერთი version-იდან მეორეზე | new_entries_only, migrate_all strategies |
| **BYOK** | Bring Your Own Key — community edition-ში user-ი თავის LLM API key-ს იყენებს | AI features work with user's own key |
| **Operator** | Marketer/engineer building flows | არა "participant" (customer in flow) |
| **Participant** | Customer executing flow | არა "operator" (person building flows) |

## Appendix B: ძველ დოკუმენტებთან შესაბამისობა

| ძველი Phase (BRD) | ახალი Phase (Master Plan) | სტატუსი |
|-------------------|--------------------------|---------|
| Phase 0: Engine Core | Phase 0: Engine Core | ✅ Done |
| Phase 1: Visual Editor + AI | Phase 2: Open-Source Launch + AI UI | Renamed, resequenced |
| Phase 2: Full Node Set | Merged into Phase 1 (Production Readiness) | Node set already complete |
| Phase 3: Launch | Phase 2 Sprint 5 (Open-Source Preparation) | Moved earlier |
| Phase 4: Cloud | Phase 3: Cloud Launch | Same concept |
| Phase 5: Ecosystem | Phase 4: Scale & Ecosystem | Same concept |

**რატომ შეიცვალა თანმიმდევრობა**: BRD-ის Phase 1-ში UI + AI ერთად იყო. რეალობაში ჯერ engine-ის hardening სჭირდება (bugs, providers, customers), შემდეგ UI + AI. ამიტომ Production Readiness გახდა Phase 1, ხოლო UI + AI გახდა Phase 2.
