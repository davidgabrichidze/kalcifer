# Changelog

All notable changes to Kalcifer are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-07-01

Initial release — "Engine Release".

### Engine

- Flow orchestration engine on Elixir/OTP: one supervised GenServer per
  active flow instance, ETS-backed node registry, crash recovery on boot.
- 31 built-in node types across 5 categories:
  - **Triggers**: `event_entry`, `segment_entry`, `webhook_entry`
  - **Conditions**: `condition` (10 operators), `ab_split`, `frequency_cap`,
    `check_segment`, `preference_gate`, `ai_decide`, `flow_router`
  - **Waits**: `wait`, `wait_until`, `wait_for_event`
  - **Actions**: `send_email`, `send_sms`, `send_push`, `send_whatsapp`,
    `send_in_app`, `call_webhook`, `update_profile`, `add_tag`, `custom_code`,
    `track_conversion`, `memory_recall`, `ai_think`, `ai_notify`, `agent`,
    `parallel_group`, `sub_flow`
  - **End**: `exit`, `goal_reached`
- Live flow versioning with instance migration strategies and rollback.
- WaitForEvent pattern: event-driven pause/resume via Oban-scheduled jobs.
- Circuit breaker protecting channel providers; per-tenant rate limiting.
- Graph cycles supported with a per-instance execution budget.

### Channels

- Provider architecture with pluggable registry: Log (dev), Webhook
  (HMAC-signed), **SendGrid** (email, v3 API) and **Twilio** (SMS/WhatsApp).
- Delivery tracking (`pending → sent → delivered/bounced/failed`) with
  signature-verified inbound status webhooks (SendGrid ECDSA, Twilio HMAC-SHA1).

### Customers & Segments

- Customer CRUD with upsert-by-external-id, batch tag operations,
  preferences, and bounded JSON properties validation.
- Dynamic segments: rule-based evaluation both in-memory (flow context
  enrichment) and at the database level (member listing via JSONB queries).

### Analytics

- Telemetry-driven collection into daily flow/node stats (dry runs excluded),
  funnel and A/B results, conversion tracking, node execution timing,
  and a daily source-of-truth rollup job.

### API

- 50+ REST endpoints under `/api/v1` with Bearer API-key auth,
  a uniform error envelope (`{error, code, message, details?, suggestion?}`),
  NimbleOptions request validation, and WebSocket flow monitoring.

### AI

- Multi-provider client (Anthropic/OpenAI/Google) with BYOK support.
- Chat copilot with 13 tools: flow CRUD/graph editing, analysis, debugging,
  session classification, and operator memory.
- AI nodes with per-node model override; council deliberation flow template.

### Frontend

- React 19 + ReactFlow visual editor: drag-drop palette covering all node
  types, node groups (Ctrl+G), sub-flow configuration, undo/redo,
  copy/paste, validation overlay, simulation (dry-run) mode, live mode with
  real-time instance tracking, instance timeline and node analytics overlays.
- Chat-driven flow building with streaming agent activity.
- Multi-theme UI, Google OAuth login, tenant switcher.

### Distribution

- `docker compose up` one-command setup (Postgres 16 + migrations + app).
- CI (test/lint/dialyzer), tag-triggered GitHub Releases with binary
  artifacts, and Docker image publishing to ghcr.io.
- Apache 2.0 license.

[0.1.0]: https://github.com/davidgabrichidze/kalcifer/releases/tag/v0.1.0
