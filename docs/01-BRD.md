# Kalcifer — Business Requirements Document

**Version**: 1.0
**Date**: 2026-02-22
**Status**: Draft

---

## 1. Executive Summary

Kalcifer is an open-source, self-hosted visual customer journey orchestration engine built on Elixir/OTP. It enables marketing and product teams to design, execute, and monitor multi-channel customer journeys through an intuitive drag-and-drop interface, powered by an execution engine engineered for extreme reliability, concurrency, and performance.

### Core Thesis

The Marketing Automation market ($15B+) is dominated by expensive, closed-source SaaS platforms (Braze, Iterable, Customer.io, Klaviyo). There is no production-grade, open-source, self-hosted visual customer journey builder. Kalcifer fills this gap with a technically superior execution engine and a focused feature set.

### Differentiators

1. **AI-first Journey Design** — No more drag-and-drop suffering. Describe your journey in plain language, upload a strategy document (Excel/CSV/Word), or have a conversation with AI — and get a production-ready journey graph. Then refine visually or through further AI dialogue. The visual editor exists for fine-tuning, not as the primary creation method.
2. **Engineered Reliability** — BEAM/OTP fault-tolerant execution. Every journey instance is an isolated process. One failure never cascades. Verified through rigorous automated testing under laboratory-grade stress conditions.
3. **Live Journey Versioning** — Update a 6-month journey mid-flight. Active customers migrate to the new version intelligently — no need to stop, rebuild, and restart. Node mapping, migration rules, and gradual rollout built-in.
4. **Real-time Event Reactivity** — Native `WaitForEvent` pattern. "Send email, wait until customer opens OR 3 days pass, whichever comes first." No polling, no workarounds.
5. **Purpose-built for Customer Journeys** — Not a generic workflow tool. Every node, every concept is designed for customer engagement use cases.
6. **Self-hosted & Open Source** — Docker Compose deployment. Full data sovereignty. No per-message pricing.
7. **Battle-tested by Design** — Comprehensive chaos testing, property-based testing, load testing baked into CI. Every release publishes a public reliability report.

---

## 2. Problem Statement

### Current Market Pain Points

**Cost**: Braze charges $50K+/year. Customer.io starts at $100/month but scales to thousands. Per-message pricing punishes growth.

**Vendor Lock-in**: Customer data lives in vendor's cloud. Migrating between platforms means rebuilding all journeys, templates, and integrations.

**Limited Reliability Guarantees**: Most platforms offer SLA on uptime, not on message delivery accuracy or journey execution correctness. When a journey misbehaves (wrong branch, skipped step, duplicate send), debugging is nearly impossible.

**Visual Editor Fatigue**: Marketing teams are exhausted by drag-and-drop interfaces. Building a 15-step multi-branch journey by dragging nodes and configuring each one takes hours. When the strategy lives in a Word document or spreadsheet, manually translating it to a visual flow is tedious, error-prone, and discouraging. No existing tool lets you describe a journey in natural language or upload a strategy doc and get a working flow.

**No Live Versioning**: A 6-month onboarding journey is running with 50,000 active customers. You need to change step 4. Current tools force you to: (a) stop the journey, (b) lose all active progress, (c) rebuild, (d) restart. Customers mid-journey are abandoned or receive duplicate messages. There is no way to update a live journey and migrate active customers to the new version.

**Generic Tooling Mismatch**: Teams using N8N/Temporal for customer journeys fight against tools designed for developer automation, not marketing workflows. No built-in concepts for segments, A/B testing, frequency capping, or conversion goals.

**Scalability Ceiling**: Node.js-based engines (N8N) hit concurrency limits. Running 100K concurrent journeys requires complex worker infrastructure.

### Target Users

| Persona | Need | Current Solution |
|---------|------|-----------------|
| **Growth Engineer** at Series A-C startup | Visual journey builder, self-hosted, API-first | Hacking together N8N + custom code |
| **Marketing Ops** at mid-market company | Multi-channel campaigns without $50K/year Braze contract | Customer.io or Klaviyo (limited) |
| **Platform Team** at enterprise | Embeddable journey engine inside their product | Building custom workflow engine (6+ months) |
| **CDP/MarTech Vendor** | White-label journey builder to embed in their platform | Nothing available open-source |

---

## 3. Product Vision

### 3.1 What Kalcifer IS

- An AI-powered and visual customer journey builder and execution engine
- Conversational journey design: describe what you want, get a production-ready graph
- Document-to-journey: upload Excel/CSV/Word strategy docs, get a working flow
- Live-versioned: update journeys mid-flight, migrate active customers intelligently
- Self-hosted, open-source (Apache 2.0 or similar permissive license)
- An embeddable engine with API-first design
- Purpose-built for customer engagement workflows
- Engineered for provable reliability

### 3.2 What Kalcifer is NOT

- Not a generic workflow automation tool (not competing with N8N/Zapier)
- Not a full CDP (no built-in data ingestion/unification)
- Not an email/SMS sending service (integrates with existing providers)
- Not a customer data warehouse

### 3.3 Design Principles

1. **Reliability is a Feature** — Not just "it works." Provably works. Every release includes automated chaos test results, load test benchmarks, and property-based test coverage. Users can trust the engine because the evidence is public.

2. **Simplicity Over Features** — 20 well-designed nodes beat 400 half-baked ones. Every node must be thoroughly tested, documented, and battle-hardened before inclusion.

3. **Embed-first** — The engine should be embeddable in other products via API. The visual editor is a standalone component that can be embedded in any frontend.

4. **Data Stays Home** — Self-hosted by default. No phone-home, no telemetry without consent, no cloud dependency.

5. **AI-era Quality Standards** — In a world where AI writes code, the competitive advantage shifts to quality, resilience, scalability, performance, lightness, and readiness. Kalcifer is built for this era.

---

## 4. Functional Requirements

### 4.1 AI Journey Designer (Primary Creation Method)

**FR-1.1**: Users can describe a journey in natural language via a conversational AI interface and receive a complete, valid journey graph.
**FR-1.2**: Users can upload strategy documents (Excel, CSV, Word, PDF) and AI generates a journey graph based on the content.
**FR-1.3**: AI understands domain concepts: segments, channels, wait conditions, A/B tests, frequency caps, exit criteria, conversion goals.
**FR-1.4**: AI-generated journeys are immediately valid and executable — no manual fixing required.
**FR-1.5**: Users can iteratively refine AI-generated journeys through follow-up conversation ("make the wait 5 days instead of 3", "add SMS fallback for non-openers", "add an A/B test on the first email").
**FR-1.6**: AI can explain an existing journey in natural language ("what does this journey do?").
**FR-1.7**: AI can suggest optimizations for existing journeys based on analytics data ("open rate on step 3 is low — consider adding a reminder").
**FR-1.8**: All AI-generated changes are previewed as a visual diff before applying.

### 4.2 Visual Editor (Refinement & Monitoring)

**FR-2.1**: Users can view and fine-tune journeys using a visual drag-and-drop canvas.
**FR-2.2**: Canvas supports nodes (actions) and edges (connections between actions).
**FR-2.3**: Edges support conditional branching (true/false paths from condition nodes).
**FR-2.4**: Users can configure each node via a properties panel.
**FR-2.5**: Canvas validates journey structure (no orphan nodes, no cycles, valid connections).
**FR-2.6**: Journeys can be saved as drafts, activated, paused, and archived.
**FR-2.7**: Visual editor is a standalone embeddable component (Web Component or npm package).
**FR-2.8**: Visual editor shows real-time execution overlay (customer counts per node, flow animation).

### 4.3 Journey Versioning & Live Migration

**FR-3.1**: Every journey change creates a new immutable version (v1, v2, v3...).
**FR-3.2**: Active journey instances are always associated with a specific version.
**FR-3.3**: Publishing a new version allows selecting a migration strategy:
  - **New entries only**: Existing instances continue on their current version, new entries use the new version.
  - **Migrate all**: All active instances migrate to the new version (with node mapping).
  - **Gradual rollout**: X% of active instances migrate, increasing over time.
**FR-3.4**: Version migration includes **node mapping** — the system (or AI) proposes how nodes in the old version correspond to nodes in the new version.
**FR-3.5**: When a node exists in both versions (mapped), customers at that node continue from the equivalent position in the new version.
**FR-3.6**: When a customer is at a node that was **removed** in the new version, configurable behavior:
  - Skip to the next mapped node downstream
  - Exit the journey gracefully
  - Hold at current position until manual review
**FR-3.7**: When a new node was **inserted** before the customer's current position, it is skipped (customer does not go backwards).
**FR-3.8**: Version diff view shows exactly what changed between versions (added nodes, removed nodes, changed configs, changed edges).
**FR-3.9**: Rollback: revert to a previous version with the same migration strategies.
**FR-3.10**: Version history with full audit trail (who changed what, when, why).

### 4.4 Journey Execution

**FR-4.1**: Each journey execution creates an isolated runtime instance per customer, **pinned to a specific journey version**.
**FR-4.2**: Journey instances survive process crashes (state persisted to database).
**FR-4.3**: Journey instances support pause/resume at any point.
**FR-4.4**: Execution supports parallel branches (customer in multiple paths simultaneously).
**FR-4.5**: Journey-wide exit criteria can remove customer from journey at any point.
**FR-4.6**: Frequency capping enforced across all journeys (global limit per customer per channel per time window).
**FR-4.7**: When a new version is published with migration strategy, running instances receive a migration command and transition to the new version graph according to the node mapping.

### 4.5 Entry Nodes

**FR-5.1 Segment Entry**: Customer enters journey when they match a segment definition. Segment evaluation is pluggable (bring your own segment engine).
**FR-5.2 Event Entry**: Customer enters journey when a specific event is received via API/webhook.
**FR-5.3 Webhook Entry**: External system triggers journey entry via HTTP POST.
**FR-5.4 Scheduled Entry**: Journey evaluates entry criteria on a cron schedule.
**FR-5.5 Manual Entry**: API call to enroll specific customers.

### 4.6 Channel Nodes

**FR-6.1 SendEmail**: Renders template, sends via pluggable provider (SendGrid, SES, SMTP, custom).
**FR-6.2 SendSMS**: Sends via pluggable provider (Twilio, MessageBird, custom).
**FR-6.3 SendPush**: Sends via pluggable provider (FCM, APNS, custom).
**FR-6.4 SendWhatsApp**: Sends via pluggable provider (Twilio, custom).
**FR-6.5 CallWebhook**: HTTP POST/PUT to external URL with customer context.
**FR-6.6**: All channel nodes support template rendering with customer attributes.
**FR-6.7**: All channel nodes report delivery status back to journey (sent, delivered, bounced, failed).

### 4.7 Logic Nodes

**FR-7.1 Wait**: Pause journey for specified duration (minutes, hours, days).
**FR-7.2 WaitUntil**: Pause until specific datetime.
**FR-7.3 WaitForEvent**: Pause until customer event received OR timeout, whichever first. **This is a key differentiator.**
**FR-7.4 Condition**: Evaluate boolean expression against customer attributes. Routes to true/false branch.
**FR-7.5 ABSplit**: Randomly split traffic into 2-5 variants with configurable percentages.
**FR-7.6 FrequencyCap**: Check if customer has exceeded contact frequency. Routes to "within cap" or "exceeded" branch.

### 4.8 Data Nodes

**FR-8.1 UpdateProfile**: Set/update customer attributes via pluggable profile store.
**FR-8.2 AddTag / RemoveTag**: Manage customer tags.
**FR-8.3 CustomCode**: Execute user-defined logic in sandboxed environment (Lua or JavaScript).

### 4.9 Exit Nodes

**FR-9.1 GoalReached**: Mark conversion event. Journey can continue or exit after goal.
**FR-9.2 JourneyExit**: Explicit journey termination.
**FR-9.3 Global Exit Criteria**: Journey-level condition evaluated at every step. If true, customer exits regardless of current position.

### 4.10 Monitoring & Analytics

**FR-10.1**: Real-time visualization of journey execution (how many customers at each node), **including per-version breakdown**.
**FR-10.2**: Per-node metrics (entered, completed, failed, average duration).
**FR-10.3**: Journey-level metrics (total entered, total converted, conversion rate, drop-off funnel).
**FR-10.4**: Individual customer journey trace (timeline of every node visited with timestamps, **including version transitions**).
**FR-10.5**: Alerting on anomalies (spike in failures, delivery rate drop).
**FR-10.6**: Version migration dashboard — progress of ongoing migrations, success/failure rates, instances per version.

### 4.11 API

**FR-11.1**: RESTful API for all operations (CRUD journeys, trigger entries, query status).
**FR-11.2**: WebSocket/SSE for real-time execution monitoring.
**FR-11.3**: Webhook registration for journey events (customer entered, goal reached, exited).
**FR-11.4**: AI conversation API for journey design (streaming).
**FR-11.5**: Document upload API (Excel/CSV/Word/PDF → journey graph).
**FR-11.6**: Journey version management API (publish, migrate, rollback, diff).
**FR-11.7**: GraphQL API (phase 2).

### 4.12 Multi-tenancy

**FR-12.1**: Single instance supports multiple tenants (workspaces).
**FR-12.2**: Complete data isolation between tenants.
**FR-12.3**: Per-tenant rate limiting and resource quotas.

---

## 5. Non-Functional Requirements

### 5.1 Performance

**NFR-1.1**: Support 100,000+ concurrent journey instances per node.
**NFR-1.2**: Node execution latency < 50ms (p99) for logic nodes.
**NFR-1.3**: Event ingestion throughput > 10,000 events/second per node.
**NFR-1.4**: Journey start latency < 200ms from trigger to first node execution.

### 5.2 Reliability

**NFR-2.1**: Zero message loss — every channel node execution must be persisted before send attempt.
**NFR-2.2**: Exactly-once semantics for channel nodes (no duplicate sends).
**NFR-2.3**: Automatic recovery from process crashes (OTP supervisor restarts).
**NFR-2.4**: Graceful degradation under load (backpressure, not crash).
**NFR-2.5**: State consistency — journey state must be recoverable from persistent storage after full system restart.

### 5.3 Scalability

**NFR-3.1**: Horizontal scaling via distributed Erlang clustering.
**NFR-3.2**: Stateless API layer (any node can handle any request).
**NFR-3.3**: Database connection pooling and query optimization for 1M+ customer profiles.

### 5.4 Observability

**NFR-4.1**: Structured logging (JSON) with correlation IDs per journey instance.
**NFR-4.2**: OpenTelemetry traces for every node execution.
**NFR-4.3**: Prometheus metrics exported for all system and business metrics.
**NFR-4.4**: Health check endpoints for orchestration (Kubernetes, Docker).

### 5.5 Security

**NFR-5.1**: API authentication via API keys and JWT.
**NFR-5.2**: RBAC for journey management (viewer, editor, admin).
**NFR-5.3**: Encrypted secrets storage for channel provider credentials.
**NFR-5.4**: Audit log for all configuration changes.
**NFR-5.5**: Sandboxed execution for CustomCode nodes (no filesystem, no network beyond whitelist).

---

## 6. User Stories

### Journey Creator

```
US-1: As a marketing manager, I want to describe a journey in plain language
      ("send welcome email, wait 3 days, if not opened send SMS reminder,
      if opened send upsell after 1 week") and get a working journey graph,
      so that I don't spend hours dragging nodes around.

US-2: As a marketing ops person, I want to upload my campaign strategy Excel
      (with steps, timing, segments, channel assignments) and get a journey
      automatically generated, so that my planning documents become executable.

US-3: As a growth engineer, I want to refine an AI-generated journey by
      saying "add an A/B test on the first email with 70/30 split"
      so that I can iterate quickly without manual graph editing.

US-4: As a marketing ops person, I want to A/B test two email variants
      so that I can optimize open rates before scaling to full audience.

US-5: As a growth engineer, I want to set "wait for event OR timeout"
      so that I can build responsive journeys that react to customer behavior.

US-6: As a marketing ops person, I want frequency capping across journeys
      so that customers don't receive more than 2 messages per day.

US-7: As a journey creator, I want to define exit criteria
      so that customers who convert are automatically removed from the journey.
```

### Journey Versioning

```
US-8: As a marketing manager, I want to update step 4 of a running 6-month
      journey and have the change apply to all 50,000 active customers,
      so that I don't have to stop and restart the entire journey.

US-9: As a cautious ops person, I want to publish a new version to only 10%
      of active instances first, monitor for problems, then migrate the rest,
      so that risky changes don't affect everyone at once.

US-10: As a growth engineer, I want to see a visual diff between journey
       versions (added/removed/changed nodes), so that I can review changes
       before publishing.

US-11: As a marketing manager, I want to rollback to a previous journey
       version if the new one performs worse, so that I can undo bad changes.

US-12: As a support engineer, I want to see which version each customer is
       on and when they migrated, so that I can debug version-specific issues.
```

### Platform Engineer

```
US-13: As a platform engineer, I want to embed Kalcifer in my product
       so that my users can build customer journeys within my application.

US-14: As a platform engineer, I want a plugin SDK
       so that I can create custom nodes for my specific use cases.

US-15: As a DevOps engineer, I want Docker Compose deployment
       so that I can run Kalcifer in my infrastructure in under 10 minutes.

US-16: As a DevOps engineer, I want Prometheus metrics and health checks
       so that I can monitor Kalcifer alongside my other services.
```

### Journey Monitor

```
US-17: As a marketing manager, I want real-time journey analytics
       so that I can see how many customers are at each step right now.

US-18: As a support engineer, I want to trace a specific customer's journey
       so that I can debug why they received (or didn't receive) a message.

US-19: As an ops engineer, I want alerts on journey anomalies
       so that I can react to delivery failures before they impact campaigns.
```

---

## 7. Success Metrics

### Product Metrics

| Metric | Target (6 months) | Target (12 months) |
|--------|-------------------|---------------------|
| GitHub Stars | 2,000 | 10,000 |
| Docker pulls | 5,000 | 50,000 |
| Active deployments (telemetry opt-in) | 100 | 1,000 |
| Community contributors | 10 | 50 |
| Cloud (managed) customers | 5 | 50 |

### Engineering Quality Metrics (Published per Release)

| Metric | Target |
|--------|--------|
| Unit test coverage | > 90% |
| Property-based test scenarios | > 500 |
| Chaos test survival rate | > 99.9% |
| Load test: concurrent journeys sustained | > 100K |
| Load test: events/sec sustained | > 10K |
| Mean recovery time after crash | < 5 seconds |
| Zero-downtime deployment verified | Yes |

---

## 8. Competitive Landscape

| Feature | Kalcifer | N8N | Braze | Customer.io | Temporal |
|---------|-----------|-----|-------|-------------|----------|
| **AI journey design** | **Yes (conversation + doc upload)** | No | No | No | No |
| **Live journey versioning** | **Yes (migrate active instances)** | No | No | Limited (stop/restart) | No |
| Visual journey builder | Yes (for refinement) | Yes (generic) | Yes | Yes | No |
| Customer journey focus | Yes | No | Yes | Yes | No |
| Self-hosted | Yes | Yes | No | No | Yes |
| Open source | Yes (permissive) | Fair-code (restricted) | No | No | Yes |
| WaitForEvent node | Yes (native) | No | Limited | Limited | Yes (code) |
| A/B testing node | Yes | No | Yes | Yes | No |
| Frequency capping | Yes | No | Yes | Limited | No |
| Concurrent journeys (per node) | 100K+ | ~1K (worker) | Unknown | Unknown | 100K+ |
| Fault isolation | Per-journey process | Per-worker | Unknown | Unknown | Per-workflow |
| Published reliability report | Yes | No | No (SLA only) | No | No |
| Embeddable engine | Yes (API-first) | Limited | No | No | Yes |
| Pricing | Free / Cloud option | Free / Enterprise | $50K+/yr | $100+/mo | Free / Cloud |

---

## 9. Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Elixir hiring difficulty | High | Medium | Strong documentation, contributor-friendly codebase, Elixir community engagement |
| Visual editor complexity underestimated | High | Medium | Use ReactFlow as foundation, not custom canvas |
| Adoption requires integrations | Medium | High | Webhook node covers 80% of cases; plugin SDK for custom nodes |
| Enterprise customers need SOC2/compliance | Medium | Medium | Cloud offering handles compliance; self-hosted puts responsibility on customer |
| Competing open-source project emerges | Medium | Low | Speed to market + reliability reputation = moat |

---

## 10. Phased Delivery

| Phase | Duration | Deliverables | Goal |
|-------|----------|-------------|------|
| **Phase 0: Engine Core** | 6 weeks | Execution engine, 5 core nodes, **journey versioning**, REST API, PostgreSQL persistence, comprehensive test suite | Prove the engine works, is reliable, and supports live versioning |
| **Phase 1: Visual Editor + AI Designer** | 8 weeks | ReactFlow-based editor, **AI conversational journey builder**, **document upload (Excel/CSV/Word)**, real-time monitoring, basic dashboard | Make it usable by non-engineers — AI as primary creation method |
| **Phase 2: Full Node Set** | 6 weeks | All 20 nodes, channel integrations, Elasticsearch/ClickHouse integration, **live migration engine** | Production-ready feature set with live versioning |
| **Phase 3: Launch** | 4 weeks | Docker Compose, docs, landing page, open-source release | Public launch |
| **Phase 4: Cloud** | 8 weeks | Managed hosting, billing, onboarding | Revenue generation |
| **Phase 5: Ecosystem** | Ongoing | Plugin SDK, marketplace, community nodes, **AI optimization suggestions** | Network effects |

---

## Appendix A: Glossary

| Term | Definition |
|------|-----------|
| **Journey** | A directed acyclic graph (DAG) of nodes that defines a multi-step customer engagement flow |
| **Journey Version** | An immutable snapshot of a journey graph. Each edit creates a new version. Active instances can migrate between versions |
| **Node** | A single action or decision point in a journey (send email, wait, condition, etc.) |
| **Edge** | A connection between two nodes defining execution order |
| **Journey Instance** | A runtime execution of a journey for a specific customer, pinned to a specific version |
| **Entry** | The trigger that causes a customer to enter a journey |
| **Exit Criteria** | A condition that removes a customer from a journey regardless of current position |
| **Frequency Cap** | A limit on how many messages a customer can receive per channel per time window |
| **WaitForEvent** | A node that pauses until a specific customer event is received or a timeout expires |
| **Node Mapping** | A correspondence table between nodes in version N and version N+1, used during live migration to determine where customers should continue |
| **Migration Strategy** | The policy for how active instances transition to a new version: new-entries-only, migrate-all, or gradual-rollout |
| **AI Designer** | The conversational interface where users describe journeys in natural language or upload documents to generate journey graphs |
| **Visual Diff** | Side-by-side comparison of two journey versions showing added, removed, and changed nodes/edges |
