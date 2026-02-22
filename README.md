# Kalcifer

Visual customer journey orchestration engine built on Elixir/OTP.

Kalcifer enables marketing and product teams to design, execute, and monitor multi-channel customer journeys through an AI-powered conversational interface and a visual drag-and-drop editor.

## Features

- **AI-first journey design** — Describe journeys in plain language or upload strategy documents
- **Visual editor** — ReactFlow-based drag-and-drop journey builder
- **Live journey versioning** — Update running journeys mid-flight with safe customer migration
- **WaitForEvent pattern** — Pause until customer events occur or timeouts expire
- **20 node types** — Entry, channel (email/SMS/push/WhatsApp), logic, data, and exit nodes
- **Multi-channel** — Email, SMS, push notifications, WhatsApp, webhooks
- **Fault-tolerant** — Per-journey process isolation on the BEAM VM
- **Self-hosted** — Full data sovereignty, Apache 2.0 license

## Tech Stack

- **Backend**: Elixir/OTP, Phoenix, Ecto, Oban, Broadway
- **Database**: PostgreSQL (primary), Elasticsearch (segments), ClickHouse (analytics)
- **Frontend**: React, ReactFlow, TypeScript, Tailwind CSS (separate package)

## Getting Started

### Prerequisites

- Elixir >= 1.17
- Erlang/OTP >= 27
- PostgreSQL 16+

### Setup

```bash
# Install dependencies
mix setup

# Start the server
mix phx.server
```

The API will be available at `http://localhost:4000/api/v1`.

### With Docker

```bash
# Start PostgreSQL, Elasticsearch, and ClickHouse
docker compose -f docker/docker-compose.yml up -d

# Then run the Elixir app locally
mix setup
mix phx.server
```

### Health Check

```bash
curl http://localhost:4000/api/v1/health
# => {"status":"ok"}
```

## Project Structure

```
lib/
├── kalcifer/              # Business logic
│   ├── application.ex     # OTP supervision tree
│   ├── repo.ex            # Ecto repository
│   ├── tenants/           # Multi-tenancy
│   ├── journeys/          # Journey definitions (CRUD)
│   ├── engine/            # Execution engine (OTP core)
│   │   └── nodes/         # Node implementations
│   ├── versioning/        # Journey versioning & live migration
│   ├── ai_designer/       # AI journey design
│   ├── customers/         # Customer profile abstraction
│   ├── channels/          # Channel provider abstraction
│   └── analytics/         # ClickHouse analytics pipeline
│
└── kalcifer_web/          # Phoenix web layer
    ├── controllers/       # REST API controllers
    ├── channels/          # WebSocket channels
    └── plugs/             # Authentication, rate limiting
```

## Documentation

Detailed documentation is available in the [docs/](docs/) directory:

- [Business Requirements](docs/01-BRD.md)
- [Architecture](docs/02-ARCHITECTURE.md)
- [Technical Specifications](docs/03-TECH-SPECS.md)
- [Testing Strategy](docs/04-TESTING-STRATEGY.md)
- [Deployment](docs/05-DEPLOYMENT.md)
- [Monetisation](docs/06-MONETISATION.md)

## License

Apache 2.0
