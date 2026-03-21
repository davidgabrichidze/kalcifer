# Kalcifer — Open-Source Launch Roadmap

**Version**: 1.0
**Date**: 2026-03-21
**Status**: ⚠️ Superseded — შინაარსი გაერთიანდა `00-MASTER-PLAN.md`-ში

> **ეს დოკუმენტი არ არის source of truth.** მისი შინაარსი სრულად შევიდა Master Plan-ში.
> იხ. **`00-MASTER-PLAN.md`** §4 (განვითარების გეგმა) და §6 (Go-to-Market).

---

## Executive Summary

Kalcifer-ს ვაქცევთ production-ready, open-source flow orchestration engine-ად AI-first UI-ით. მიზანია AI სერვისების გადაყიდვა managed platform-ის სახით. ეს დოკუმენტი აღწერს კონკრეტულ გეგმას 4 ფაზაში, 16-კვირიან ჰორიზონტზე.

```
ფაზა 1 (კვირა 1-4):   Production Readiness — ბაგ ფიქსები, hardening, Docker
ფაზა 2 (კვირა 5-8):   Open-Source Launch — repo, docs, community, GitHub release
ფაზა 3 (კვირა 9-12):  AI-Enabled UI — flow builder, AI copilot, React frontend
ფაზა 4 (კვირა 13-16): Cloud Launch — Fly.io deploy, billing, onboarding
```

---

## ფაზა 1: Production Readiness (კვირა 1–4)

### 1.1 Critical Bug Fixes (კვირა 1)

PHASE-1.md-ში აღწერილი 8 known_bug-ის გამოსწორება:

| # | ბაგი | პრიორიტეტი |
|---|------|-----------|
| C1 | Cross-tenant event injection (security) | P0 |
| C3 | ResumeFlowJob dead process handling | P0 |
| C6/I13 | wait_until migration atom + missing arm | P0 |
| C9 | nil customer_id dedup crash | P1 |
| I1 | FlowInstance status state machine | P1 |
| I5 | Invalid migration strategy 500 | P2 |
| T5 | Same-version migration 500 | P2 |
| N4 | AbSplit empty variants crash | P2 |

**Definition of Done**: ყველა `@tag :known_bug` მოხსნილი, 0 failures

### 1.2 Input Validation & Error Handling (კვირა 1-2)

- [ ] API request validation — `nimble_options`-ით schema validation ყველა endpoint-ზე
- [ ] Consistent error responses — `{error, code, message, details}` ფორმატი
- [ ] Rate limiting production-ready — `Kalcifer.RateLimiter` GenServer-ით (არა plug-only)
- [ ] Request ID propagation — `x-request-id` header მთელ pipeline-ში

### 1.3 Channel Provider Architecture (კვირა 2-3)

LogProvider-ების ნაცვლად რეალური პროვაიდერები:

```
lib/kalcifer/channels/providers/
├── log_provider.ex          # (არსებული) — dev/test
├── sendgrid_provider.ex     # Email — SendGrid API
├── twilio_provider.ex       # SMS — Twilio API
├── webhook_provider.ex      # (არსებული) — generic webhook
└── provider_behaviour.ex    # Behaviour: send/2, status/1, validate_config/1
```

**Minimum Viable Channels** (open-source release-ისთვის):
1. **Email** — SendGrid (ან SMTP fallback)
2. **SMS** — Twilio
3. **Webhook** — არსებული, გაუმჯობესებული retry-ით
4. WhatsApp, Push, In-App — stub-ად დარჩება, community-ს შეავსებინებ

### 1.4 Customer Data Model (კვირა 3)

- [ ] Customer CRUD სრულად ფუნქციონალური
- [ ] Segment evaluator — real queries (არა stub)
- [ ] Customer properties — JSON schema validation
- [ ] Tags system — batch operations-ით

### 1.5 Docker & Local Dev (კვირა 4)

- [ ] `docker-compose.yml` — one-command setup: `docker compose up`
- [ ] PostgreSQL 16 + app (Elasticsearch/ClickHouse optional-ად)
- [ ] Health check endpoint production-ready
- [ ] `make` targets: `make setup`, `make dev`, `make test`, `make release`
- [ ] `.env.example` ყველა env var-ით

**Target**: `git clone → docker compose up → working API in 2 minutes`

---

## ფაზა 2: Open-Source Launch (კვირა 5–8)

### 2.1 Repository Preparation (კვირა 5)

#### ლიცენზირება

```
LICENSE                      # Apache 2.0 (core engine)
LICENSE-ENTERPRISE           # Proprietary (cloud/enterprise features)
```

**Apache 2.0 მოიცავს**:
- Execution engine (ყველა 24 node)
- REST + WebSocket API
- Docker deployment
- Plugin SDK
- Single-tenant mode

**Proprietary მოიცავს** (ცალკე repo ან `/ee` directory):
- Multi-tenancy
- AI Copilot (managed LLM)
- SSO/SAML
- Advanced analytics (ClickHouse)
- Audit log
- White-label

#### Repo Structure (GitLab → GitHub mirror)

```
kalcifer/
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                # Test + lint + dialyzer
│   │   ├── release.yml           # Auto-release on tag
│   │   └── docker-publish.yml    # Push to ghcr.io
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml
│   │   └── feature_request.yml
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── FUNDING.yml
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── CHANGELOG.md
├── LICENSE
├── README.md                     # გადაკეთებული, community-ფოკუსი
└── docs/
    ├── getting-started.md
    ├── architecture.md
    ├── api-reference.md
    ├── node-development.md       # Plugin SDK guide
    └── deployment.md
```

### 2.2 CI/CD Pipeline (კვირა 5-6)

#### GitHub Actions: ci.yml

```yaml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: kalcifer_test
          POSTGRES_PASSWORD: kalcifer_test
          POSTGRES_DB: kalcifer_test
        ports: ["5432:5432"]
        options: --health-cmd pg_isready

    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '28'
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix format --check-formatted
      - run: mix credo --strict
      - run: mix test --trace
      - run: mix dialyzer
```

#### Docker Publish: docker-publish.yml

```yaml
name: Publish Docker
on:
  push:
    tags: ['v*']

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v5
        with:
          context: .
          file: docker/Dockerfile
          push: true
          tags: |
            ghcr.io/${{ github.repository }}:${{ github.ref_name }}
            ghcr.io/${{ github.repository }}:latest
```

### 2.3 Documentation (კვირა 6-7)

**Doc site**: [docs.kalcifer.dev](https://docs.kalcifer.dev) — ExDoc ან MkDocs Material

#### Getting Started Guide

```markdown
# Quick Start

## Option 1: Docker (recommended)
curl -fsSL https://get.kalcifer.dev | sh
# ან
docker compose -f docker-compose.yml up -d

## Option 2: From source
git clone https://github.com/kalcifer/kalcifer
cd kalcifer && mix setup && mix phx.server

## Create your first flow
curl -X POST http://localhost:4500/api/v1/flows \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "Welcome Flow", "graph": {...}}'
```

#### API Reference

- OpenAPI 3.1 spec — auto-generated ან hand-maintained
- Interactive playground — Swagger UI ან Redoc
- Code examples — cURL, Python, JavaScript, Elixir

#### Node Development Guide

```markdown
# Building Custom Nodes

1. Implement NodeBehaviour
2. Register in NodeRegistry
3. Test with factory helpers
4. (Optional) Publish to community registry
```

### 2.4 Launch Checklist (კვირა 8)

- [ ] README გადაწერილი — hero section, demo GIF, quick start
- [ ] CHANGELOG.md — v0.1.0 initial release
- [ ] GitHub Releases — binary artifacts + Docker image
- [ ] Hex.pm publish (optional — Elixir package manager)
- [ ] Hacker News / Elixir Forum / Reddit announcement
- [ ] Product Hunt launch page
- [ ] Discord / GitHub Discussions community
- [ ] Demo instance — `demo.kalcifer.dev` (read-only, pre-loaded flows)

---

## ფაზა 3: AI-Enabled UI (კვირა 9–12)

### 3.1 არქიტექტურა

```
┌─────────────────────────────────────────────────────────────┐
│                    Kalcifer Cloud UI                         │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  Flow Editor  │  │  AI Copilot  │  │  Analytics View  │  │
│  │  (ReactFlow)  │  │  (Chat + AI) │  │  (Recharts)      │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────────┘  │
│         │                 │                  │              │
│  ┌──────┴─────────────────┴──────────────────┴───────────┐  │
│  │                  API Client (TypeScript)               │  │
│  └──────────────────────┬────────────────────────────────┘  │
│                         │                                   │
└─────────────────────────┼───────────────────────────────────┘
                          │ REST + WebSocket
┌─────────────────────────┼───────────────────────────────────┐
│                  Kalcifer Backend                            │
│                         │                                   │
│  ┌──────────────────────┴────────────────────────────────┐  │
│  │              Phoenix API (არსებული)                    │  │
│  └──────┬──────────────────┬─────────────────────────────┘  │
│         │                  │                                │
│  ┌──────┴───────┐  ┌──────┴──────────────────────────────┐  │
│  │ Flow Engine  │  │  AI Service Layer (Proprietary)      │  │
│  │ (არსებული)   │  │                                     │  │
│  │              │  │  ┌─────────────┐  ┌──────────────┐  │  │
│  │              │  │  │ LLM Router  │  │ AI Features   │  │  │
│  │              │  │  │ (Multi-     │  │ • Flow Gen    │  │  │
│  │              │  │  │  provider)  │  │ • Optimization│  │  │
│  │              │  │  │             │  │ • NL → Graph  │  │  │
│  │              │  │  │ Claude API  │  │ • Smart Debug │  │  │
│  │              │  │  │ OpenAI API  │  │ • Auto-segment│  │  │
│  │              │  │  │ Gemini API  │  │               │  │  │
│  │              │  │  └─────────────┘  └──────────────┘  │  │
│  └──────────────┘  └─────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Frontend Stack

```
ui/
├── package.json
├── vite.config.ts
├── tailwind.config.ts
├── tsconfig.json
├── src/
│   ├── main.tsx
│   ├── App.tsx
│   ├── api/                      # API client (axios/fetch)
│   │   ├── client.ts
│   │   ├── flows.ts
│   │   ├── instances.ts
│   │   └── ai.ts
│   ├── components/
│   │   ├── flow-editor/          # ReactFlow-based visual editor
│   │   │   ├── FlowCanvas.tsx
│   │   │   ├── NodePalette.tsx
│   │   │   ├── nodes/            # Custom ReactFlow node renderers
│   │   │   │   ├── TriggerNode.tsx
│   │   │   │   ├── ActionNode.tsx
│   │   │   │   ├── ConditionNode.tsx
│   │   │   │   ├── WaitNode.tsx
│   │   │   │   └── EndNode.tsx
│   │   │   └── edges/
│   │   ├── ai-copilot/           # AI chat sidebar
│   │   │   ├── CopilotPanel.tsx
│   │   │   ├── MessageList.tsx
│   │   │   └── SuggestionCards.tsx
│   │   ├── dashboard/
│   │   ├── analytics/
│   │   └── common/
│   ├── hooks/
│   │   ├── useFlow.ts
│   │   ├── useWebSocket.ts
│   │   └── useAI.ts
│   ├── stores/                   # Zustand state management
│   └── types/
└── tests/
```

**Tech Stack**:
- React 19 + TypeScript
- ReactFlow — visual flow editor (MIT license)
- Zustand — state management
- Tailwind CSS + Shadcn/UI
- Vite — build tool
- Vitest — testing

### 3.3 AI Service Layer (Revenue Center)

#### AI Features Taxonomy

| Feature | Community (BYOK) | Cloud (Managed) | Revenue Model |
|---------|-------------------|-----------------|---------------|
| Flow generation from NL | ✅ (own key) | ✅ (included) | Per-conversation |
| Flow optimization suggestions | ❌ | ✅ | Per-analysis |
| Smart debugging | ✅ (own key) | ✅ (included) | Per-session |
| Auto-segmentation | ❌ | ✅ | Per-run |
| A/B test analysis | ❌ | ✅ | Per-analysis |
| Document → Flow | ✅ (own key) | ✅ (included) | Per-conversion |

**BYOK = Bring Your Own Key** — community edition-ში მომხმარებელი თავის API key-ს იყენებს

#### LLM Router Architecture

```elixir
# lib/kalcifer_cloud/ai/llm_router.ex (Proprietary)
defmodule KalciferCloud.AI.LLMRouter do
  @providers %{
    claude: KalciferCloud.AI.Providers.Claude,
    openai: KalciferCloud.AI.Providers.OpenAI,
    gemini: KalciferCloud.AI.Providers.Gemini
  }

  def complete(prompt, opts \\ []) do
    provider = opts[:provider] || default_provider()
    model = opts[:model] || default_model(provider)

    @providers[provider].complete(prompt, model, opts)
  end
end
```

#### AI API Endpoints (Cloud-only)

```
POST /api/v1/ai/generate-flow        # NL → Flow graph JSON
POST /api/v1/ai/optimize             # Flow → optimization suggestions
POST /api/v1/ai/debug                # Instance error → root cause
POST /api/v1/ai/segment              # Customer data → auto-segments
POST /api/v1/ai/analyze-ab           # A/B results → insights
POST /api/v1/ai/document-to-flow     # Document upload → Flow
```

#### Revenue Model

```
AI API pricing (Cloud tier):
├── Starter ($299/mo):  1,000 AI conversations/month included
├── Growth ($999/mo):   5,000 AI conversations/month included
├── Scale ($2,999/mo):  Unlimited AI conversations
└── Overage:            $0.10 per additional conversation

Estimated unit economics:
├── Avg LLM cost per conversation: ~$0.03 (Claude Haiku/Sonnet mix)
├── Revenue per conversation: $0.10-0.30
└── Gross margin on AI: ~70-90%
```

### 3.4 UI Prototype → Production (კვირა 9-12)

არსებული `ui-prototype/` HTML ფაილები გარდაიქმნება React app-ად:

| Prototype | Production Component | კვირა |
|-----------|---------------------|-------|
| `main.html` | Dashboard + Flow list | 9 |
| `engine-room.html` | Flow Editor (ReactFlow) | 10-11 |
| `browse.html` | Node browser + AI Copilot | 11-12 |

---

## ფაზა 4: Cloud Launch on Fly.io (კვირა 13–16)

### 4.1 Fly.io Configuration

#### fly.toml

```toml
app = "kalcifer"
primary_region = "fra"          # Frankfurt (Europe)
kill_signal = "SIGTERM"
kill_timeout = "30s"

[build]
  dockerfile = "docker/Dockerfile"

[env]
  PHX_HOST = "app.kalcifer.dev"
  PORT = "4500"
  ECTO_IPV6 = "true"
  ERL_AFLAGS = "-proto_dist inet6_tcp"
  POOL_SIZE = "20"
  RELEASE_COOKIE = "kalcifer-cookie"

[http_service]
  internal_port = 4500
  force_https = true
  auto_stop_machines = false
  auto_start_machines = true
  min_machines_running = 2

  [http_service.concurrency]
    type = "connections"
    hard_limit = 1000
    soft_limit = 800

[[vm]]
  size = "performance-2x"       # 4 CPU, 8GB RAM
  memory = "4gb"
  processes = ["app"]

[checks]
  [checks.health]
    port = 4500
    type = "http"
    interval = "10s"
    timeout = "5s"
    grace_period = "30s"
    method = "GET"
    path = "/api/v1/health"
```

#### Fly.io Setup Commands

```bash
# App + Database
fly apps create kalcifer
fly postgres create --name kalcifer-db --region fra --vm-size shared-cpu-2x
fly postgres attach kalcifer-db --app kalcifer

# Secrets
fly secrets set \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  SENDGRID_API_KEY=SG.xxx \
  TWILIO_ACCOUNT_SID=xxx \
  TWILIO_AUTH_TOKEN=xxx \
  CLAUDE_API_KEY=sk-ant-xxx \
  OPENAI_API_KEY=sk-xxx \
  STRIPE_SECRET_KEY=sk_live_xxx

# Deploy
fly deploy

# Scale (production)
fly scale count 3 --region fra,cdg,ams
fly autoscale set min=2 max=10
```

### 4.2 BEAM Clustering on Fly.io

```elixir
# config/runtime.exs
config :libcluster,
  topologies: [
    fly6pn: [
      strategy: Cluster.Strategy.DNSPoll,
      config: [
        polling_interval: 5_000,
        query: "#{System.get_env("FLY_APP_NAME")}.internal",
        node_basename: System.get_env("FLY_APP_NAME")
      ]
    ]
  ]
```

BEAM clustering-ის უპირატესობა Fly.io-ზე:
- FlowServer GenServer-ები distribute ხდება ინსტანსებზე
- PubSub broadcasts ქლასტერში
- Zero-downtime deploys rolling strategy-ით

### 4.3 Multi-Tenant Architecture (Cloud)

```elixir
# lib/kalcifer_cloud/tenants/tenant.ex
defmodule KalciferCloud.Tenants.Tenant do
  schema "cloud_tenants" do
    field :name, :string
    field :slug, :string
    field :plan, :string                    # starter | growth | scale
    field :stripe_customer_id, :string
    field :stripe_subscription_id, :string
    field :ai_conversations_used, :integer, default: 0
    field :ai_conversations_limit, :integer
    field :features, :map                   # feature flags

    has_many :api_keys, Kalcifer.Tenants.ApiKey
    has_many :flows, Kalcifer.Flows.Flow
    timestamps()
  end
end
```

### 4.4 Billing (Stripe)

```
POST /api/v1/billing/subscribe          # Create subscription
POST /api/v1/billing/portal             # Customer portal link
GET  /api/v1/billing/usage              # Current usage stats
POST /webhooks/stripe                    # Stripe webhook handler

Stripe Products:
├── prod_starter:  $299/mo — 1K AI convos
├── prod_growth:   $999/mo — 5K AI convos
├── prod_scale:    $2,999/mo — unlimited
└── Metered billing for AI overage: $0.10/conversation
```

### 4.5 Monitoring & Observability

```
Fly.io built-in:
├── Metrics (Prometheus)
├── Logs (structured JSON via LoggerJSON)
└── Health checks

External:
├── Grafana Cloud (free tier) — dashboards
├── Sentry — error tracking
├── BetterStack (or Axiom) — log aggregation
└── StatusPage — public status page (status.kalcifer.dev)

Key metrics:
├── Flow execution latency (p50, p95, p99)
├── Active instances count
├── Node execution success/failure rate
├── AI conversation count + cost
├── API response time
└── Oban queue depth
```

---

## Domain & Infrastructure Map

```
kalcifer.dev                    # Landing page (static, Cloudflare Pages)
├── app.kalcifer.dev            # Cloud UI (React app, Fly.io)
├── api.kalcifer.dev            # API (Fly.io, same app)
├── docs.kalcifer.dev           # Documentation (MkDocs, Cloudflare Pages)
├── demo.kalcifer.dev           # Demo instance (Fly.io, read-only)
├── status.kalcifer.dev         # Status page (BetterStack)
└── community.kalcifer.dev      # Discord ან GitHub Discussions redirect

github.com/kalcifer/kalcifer    # Main repo (open-source, Apache 2.0)
github.com/kalcifer/kalcifer-ui # Frontend repo (open-source, Apache 2.0)
github.com/kalcifer/docs        # Documentation repo
ghcr.io/kalcifer/kalcifer       # Docker images
```

---

## Release Strategy

### v0.1.0 — "Engine Release" (კვირა 8)
- Core engine — 24 nodes, full API
- Docker Compose one-command setup
- Getting started documentation
- 3 real channel providers (Email, SMS, Webhook)
- Apache 2.0 license

### v0.2.0 — "UI Release" (კვირა 12)
- React visual flow editor
- AI Copilot (BYOK mode for community)
- WebSocket real-time monitoring
- Node development SDK

### v1.0.0 — "Cloud Launch" (კვირა 16)
- Kalcifer Cloud on Fly.io
- Managed AI features
- Stripe billing
- Multi-tenancy
- SLA + support tiers

---

## Launch Marketing Channels

| Channel | Timing | Expected Impact |
|---------|--------|-----------------|
| Hacker News (Show HN) | v0.1.0 | 2-5K visitors, 200+ stars |
| Elixir Forum | v0.1.0 | Community credibility |
| Reddit r/elixir, r/selfhosted | v0.1.0 | Early adopters |
| Product Hunt | v0.2.0 (UI) | 1-3K visitors |
| Dev.to / Hashnode blog posts | ongoing | SEO + thought leadership |
| Twitter/X threads | ongoing | Developer awareness |
| YouTube demo video | v0.2.0 | Visual proof-of-concept |
| Discord community | v0.1.0+ | Retention + feedback |

---

## Budget Estimate (16 კვირა)

| Category | Monthly Cost | Notes |
|----------|-------------|-------|
| Fly.io (app + DB) | $50-150 | Performance VMs, Postgres |
| Domain (kalcifer.dev) | $12/year | - |
| Cloudflare Pages | Free | Landing + docs |
| Grafana Cloud | Free tier | Monitoring |
| Sentry | Free tier | Error tracking |
| Claude API (AI features) | $100-500 | Usage-dependent |
| SendGrid | Free tier (100/day) | Email provider |
| Twilio | Pay-per-use | SMS provider |
| **Total** | **~$200-700/mo** | **Pre-revenue** |

---

## Success Metrics (6 months post-launch)

| Metric | Target |
|--------|--------|
| GitHub Stars | 2,000+ |
| Docker pulls | 5,000+ |
| Weekly active self-hosted instances | 100+ |
| Cloud paying customers | 10+ |
| MRR | $5,000+ |
| Community Discord members | 500+ |
| External contributors | 20+ |
| AI conversations/month (Cloud) | 10,000+ |

---

## Next Immediate Actions

1. **ახლავე**: ბაგ ფიქსები (PHASE-1.md Increment 12)
2. **ამ კვირაში**: Docker Compose გამარტივება, `make` targets
3. **მომავალ კვირაში**: LICENSE ფაილი, CONTRIBUTING.md, CI pipeline
4. **2 კვირაში**: Channel providers (SendGrid, Twilio)
5. **3 კვირაში**: README გადაწერა, documentation site setup
