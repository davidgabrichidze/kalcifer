# Kalcifer

Flow orchestration engine built on Elixir/OTP. The core engine is domain-agnostic; marketing
automation ("Journey") is a layer on top of it.

Design flows in plain language through an AI chat, or build them by hand in a visual editor, then
run them per-customer as supervised BEAM processes.

## Features

- **AI-first flow design** — describe a flow in chat and the AI builds it, using 13 tools that
  create flows, edit the graph node by node, analyse it and debug live instances
- **Visual editor** — drag-and-drop canvas built on ReactFlow, kept in sync with the AI in both
  directions: it sees your manual edits, and the canvas refreshes on its edits
- **31 node types** across 5 categories — triggers, conditions, waits, actions
  (channel / data / AI / orchestration) and terminals
- **Live versioning** — update a running flow and migrate in-flight customers onto the new version,
  with rollback
- **Wait-for-event** — pause a flow until a matching customer event arrives, or until a timeout
- **Multi-channel** — email, SMS, push, WhatsApp, in-app and outbound webhooks, with per-tenant
  provider selection and delivery tracking
- **Provider simulators** — email/SMS/push/WhatsApp/in-app simulators emulate the asynchronous
  callbacks real providers send (bounces, opens, clicks, read receipts), so flows can be exercised
  without live keys
- **Fault-tolerant** — one supervised GenServer per running flow instance, with crash recovery on boot
- **Multi-tenant** — API-key tenants for machine callers, Google OAuth sessions for operators
- **Self-hosted** — full data sovereignty, Apache 2.0

## Tech Stack

- **Backend** — Elixir ~> 1.18 / OTP 27+, Phoenix 1.7 (API-only), Ecto, Oban, Bandit
- **Database** — PostgreSQL 16 for everything: flows, customers, segments, analytics, audit
- **Frontend** — React 19, ReactFlow (`@xyflow/react`), TypeScript, Tailwind 4, Vite — in `frontend/`
- **AI** — multi-provider: Anthropic (Claude), OpenAI, Google (Gemini)

## Getting Started

### Prerequisites

Docker, **or** Elixir 1.18 + Erlang/OTP 27+ and PostgreSQL 16.

### Option A — everything in Docker

```bash
cp .env.example .env     # required: docker-compose.dev.yml declares env_file
make up                  # postgres + app   → http://localhost:4500
make docker-setup        # deps, ecto.create, ecto.migrate
make fe                  # frontend         → http://localhost:5173
```

The `.env` file has to exist, but it can stay empty — `config/dev.exs` carries working defaults for
the database, `secret_key_base` and the session secret. Fill it in only for the optional features
below.

### Option B — Elixir on the host

```bash
docker compose -f docker-compose.dev.yml up -d postgres   # or bring your own PostgreSQL

mix setup                # deps.get + ecto.create + ecto.migrate + seed
mix phx.server           # → http://localhost:4500
```

Frontend in a second terminal:

```bash
cd frontend && npm install && npm run dev                 # → http://localhost:5173
```

### Check it works

```bash
curl http://localhost:4500/api/v1/health
# => {"status":"ok"}
```

Then open **http://localhost:5173**. Vite proxies `/api` to port 4500, so the two are same-origin.

If the server exits at boot with `:eafnosupport`, the machine has no IPv6 — dev binds `::` by
default. Start it with `BIND_IP=ipv4` to bind `0.0.0.0` instead.

No login is needed locally: with `VITE_GOOGLE_CLIENT_ID` unset the landing page offers a skip
button, and in dev the API falls back to an auto-created "Demo Tenant". Both are gated on
`:allow_tenant_header`, which is on in dev and test only — in production every request needs a real
credential.

### Optional configuration

All optional, all in `.env` (see `.env.example` for the full list):

| For | Variables |
|-----|-----------|
| AI chat | `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY` |
| Google sign-in | `VITE_GOOGLE_CLIENT_ID`, `AUTH_SESSION_SECRET` |
| Email delivery | `SENDGRID_API_KEY`, `SENDGRID_FROM_EMAIL`, … |
| SMS and WhatsApp | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, … |

Without provider keys, dev routes channel sends to the built-in simulators.

## Commands

```bash
make test        # mix test --trace
make ci          # compile --warnings-as-errors + format + credo --strict + test + dialyzer
make db-reset    # drop, create, migrate, seed
make down        # stop the Docker environment
```

`make ci` runs the same checks as GitHub Actions. Run it before opening a pull request.

## Ports

| Port | Service |
|------|---------|
| 4500 | API (dev) |
| 4502 | API (test) |
| 5173 | Frontend dev server |
| 5432 | PostgreSQL |

## Project Structure

```
lib/
├── kalcifer/                  # Business logic
│   ├── engine/                # Execution engine (OTP core)
│   │   ├── flow_server.ex     # One GenServer per running flow instance
│   │   ├── node_registry.ex   # ETS: node type string → module
│   │   ├── nodes/             # The 31 node implementations, by category
│   │   ├── jobs/              # Oban workers (delayed resume, cleanup, rollups)
│   │   └── persistence/       # InstanceStore, StepStore
│   ├── flows/                 # Flow, FlowVersion, FlowInstance, FlowGraph
│   ├── versioning/            # Live migration between flow versions
│   ├── ai/                    # Chat client, providers, tools, memory, prompts
│   ├── channels/              # Provider abstraction and delivery tracking
│   ├── customers/             # Profiles and segments
│   ├── analytics/             # Stats collection, funnels, conversions
│   ├── simulators/            # Provider simulators
│   ├── marketing/             # Journey — the marketing layer over flows
│   ├── tenants/               # Multi-tenancy and API keys
│   ├── accounts/              # Operator accounts (Google OAuth)
│   └── audit/                 # Audit log
│
└── kalcifer_web/              # Phoenix web layer
    ├── controllers/           # REST API
    ├── channels/              # WebSocket (live instance and step events)
    └── plugs/                 # Auth, tenant resolution, rate limiting

frontend/src/                  # React SPA
├── pages/                     # Work, Editor, Engine Room, Browse
├── components/                # Chat panel, canvas, shell
└── lib/                       # API client, themes, socket
```

## Documentation

- [Product Map](docs/PRODUCT-MAP.md) — what is built, and the commit scope that owns each part
- [Architecture](docs/02-ARCHITECTURE.md)
- [Technical Specifications](docs/03-TECH-SPECS.md)
- [Testing Strategy](docs/04-TESTING-STRATEGY.md)
- [Deployment](docs/05-DEPLOYMENT.md)
- [Business Requirements](docs/01-BRD.md)
- [Contributing](CONTRIBUTING.md)

Repo conventions — commit scopes, naming, testing rules — are in [CLAUDE.md](CLAUDE.md).

Several documents under `docs/` describe the original plan rather than the current build.
`docs/PRODUCT-MAP.md` is the one kept in sync with the code.

## License

Apache 2.0
