# Kalcifer — Monetisation Strategy

**Version**: 1.0
**Date**: 2026-02-22
**Status**: Draft

---

## 1. Business Model: Open Core

Kalcifer follows the **Open Core** model, proven by PostHog, GitLab, Supabase, and Cal.com:

```
┌──────────────────────────────────────────────────────┐
│                    Community Edition                   │
│                    (Apache 2.0)                        │
│                                                      │
│  Full execution engine, all 20 nodes, visual editor  │
│  PostgreSQL + ES + ClickHouse, Docker Compose deploy │
│  REST API, WebSocket, Plugin SDK                     │
│  Single tenant, no user limit                        │
│                                                      │
│  ──── This is NOT a crippled version ────            │
│  ──── This is a complete, production product ────    │
└──────────────────────────────────────────────────────┘
            │                        │
            ▼                        ▼
┌──────────────────────┐  ┌───────────────────────────┐
│   Kalcifer Cloud    │  │   Enterprise Edition      │
│   (Managed SaaS)     │  │   (Self-hosted, licensed) │
│                      │  │                           │
│  Zero-ops hosting    │  │  Multi-tenancy            │
│  Auto-scaling        │  │  SSO (SAML/OIDC)          │
│  Built-in CDN        │  │  Audit log                │
│  SOC2 compliance     │  │  RBAC (granular)          │
│  99.9% SLA           │  │  Dedicated support        │
│  Automatic backups   │  │  Custom SLA               │
│  Global regions      │  │  Priority bug fixes       │
│                      │  │  White-label              │
│  $299-2,999/mo       │  │  $999-9,999/mo            │
└──────────────────────┘  └───────────────────────────┘
```

### Why This Model Works

1. **Community Edition is genuinely complete** — not feature-gated cripple-ware. This drives adoption, trust, and contributions.
2. **Cloud sells convenience** — "I could self-host, but I'd rather not" is a $10B+ market.
3. **Enterprise sells compliance & control** — SSO, audit logs, SLA are table-stakes for enterprise procurement.

---

## 2. Pricing Tiers

### 2.1 Community (Free, forever)

**License**: Apache 2.0
**Target**: Individual developers, small startups, evaluators

| Feature | Included |
|---------|----------|
| Execution engine (full) | Yes |
| All 20 nodes | Yes |
| Visual journey editor | Yes |
| **AI journey designer** (bring your own LLM API key) | **Yes** |
| **Journey versioning** (immutable versions, diff view) | **Yes** |
| **Live migration** (new-entries-only strategy) | **Yes** |
| **Document upload** (Excel/CSV/Word → journey) | **Yes** |
| REST + WebSocket API | Yes |
| Plugin SDK | Yes |
| PostgreSQL + ES + ClickHouse | Yes |
| Docker Compose deployment | Yes |
| Prometheus metrics | Yes |
| Real-time monitoring | Yes |
| Single workspace | Yes |
| Unlimited journeys | Yes |
| Unlimited customers | Yes |
| Community support (GitHub) | Yes |

### 2.2 Cloud — Starter ($299/month)

**Target**: Growing startups (Series A/B), 10K-100K customers

| Feature | Included |
|---------|----------|
| Everything in Community | Yes |
| **AI designer with managed LLM** (no API key needed) | **Yes** |
| **All migration strategies** (migrate-all, gradual rollout) | **Yes** |
| **AI optimization suggestions** (based on analytics) | **Yes** |
| Managed hosting (single region) | Yes |
| Automatic backups (daily) | Yes |
| Auto-scaling (up to 50K concurrent journeys) | Yes |
| Email support (48h response) | Yes |
| 99.5% uptime SLA | Yes |
| 3 workspaces | Yes |
| 5 team members | Yes |
| 500K events/month | Yes |
| 1,000 AI designer conversations/month | Yes |

### 2.3 Cloud — Growth ($999/month)

**Target**: Mid-market companies, 100K-1M customers

| Feature | Included |
|---------|----------|
| Everything in Starter | Yes |
| Multi-region deployment | Yes |
| Automatic backups (hourly) | Yes |
| Auto-scaling (up to 500K concurrent journeys) | Yes |
| Priority email support (24h response) | Yes |
| 99.9% uptime SLA | Yes |
| 10 workspaces | Yes |
| 20 team members | Yes |
| 5M events/month | Yes |
| Custom domain | Yes |
| SSO (Google, GitHub) | Yes |
| Webhook retry & DLQ dashboard | Yes |

### 2.4 Cloud — Scale ($2,999/month)

**Target**: Large companies, 1M+ customers

| Feature | Included |
|---------|----------|
| Everything in Growth | Yes |
| Dedicated infrastructure | Yes |
| Automatic backups (continuous WAL) | Yes |
| Unlimited concurrent journeys | Yes |
| Dedicated support engineer | Yes |
| 99.95% uptime SLA | Yes |
| Unlimited workspaces | Yes |
| Unlimited team members | Yes |
| Unlimited events | Yes |
| Custom integrations support | Yes |
| SSO (SAML/OIDC) | Yes |
| Audit log | Yes |
| Data export (bulk) | Yes |
| SOC2 Type II report | Yes |

### 2.5 Enterprise (Self-hosted, $999-9,999/month)

**Target**: Enterprises with data sovereignty requirements

| Feature | Included |
|---------|----------|
| Everything in Community | Yes |
| Multi-tenancy support | Yes |
| SSO (SAML/OIDC) | Yes |
| Granular RBAC | Yes |
| Full audit log | Yes |
| White-label (remove Kalcifer branding) | Yes |
| Priority support (8h response, Slack channel) | Yes |
| Custom SLA | Yes |
| Kubernetes Helm chart (production-grade) | Yes |
| High-availability configuration guide | Yes |
| Annual security review | Yes |
| Roadmap input | Yes |

---

## 3. Revenue Projections

### Conservative Model (24-month horizon)

**Assumptions**:
- Launch at month 0 (open source release)
- Cloud launch at month 4
- Enterprise launch at month 8
- Growth rate: 15% MoM for Cloud, 10% MoM for Enterprise

| Month | GitHub Stars | Cloud Customers | Enterprise | Cloud MRR | Enterprise MRR | Total MRR |
|-------|-------------|-----------------|------------|-----------|----------------|-----------|
| 0 | 500 | 0 | 0 | $0 | $0 | $0 |
| 3 | 2,000 | 0 | 0 | $0 | $0 | $0 |
| 6 | 5,000 | 10 | 0 | $5K | $0 | $5K |
| 9 | 8,000 | 25 | 2 | $15K | $6K | $21K |
| 12 | 12,000 | 50 | 5 | $35K | $20K | $55K |
| 18 | 20,000 | 100 | 10 | $75K | $50K | $125K |
| 24 | 30,000 | 180 | 18 | $140K | $100K | $240K |

**Key Metric**: Conversion rate from self-hosted → Cloud = 2-5% (industry standard for open-core).

### Unit Economics

| Metric | Cloud Starter | Cloud Growth | Cloud Scale | Enterprise |
|--------|---------------|--------------|-------------|------------|
| Price | $299/mo | $999/mo | $2,999/mo | $2,500/mo avg |
| COGS (infra) | $50/mo | $150/mo | $500/mo | $0 (self-hosted) |
| Gross Margin | 83% | 85% | 83% | 100% |
| Support cost | $20/mo | $50/mo | $200/mo | $300/mo |
| Net margin | 77% | 80% | 76% | 88% |
| LTV (24mo) | $5,500 | $19,200 | $57,600 | $52,800 |
| CAC target | $500 | $2,000 | $5,000 | $5,000 |
| LTV:CAC | 11:1 | 9.6:1 | 11.5:1 | 10.6:1 |

---

## 4. Go-to-Market Strategy

### Phase 1: Community Building (Month 0-4)

**Goal**: 5,000 GitHub stars, 100 Discord members, 10 blog posts

**Channels**:

1. **Hacker News launch** — "Show HN: Open-source customer journey builder powered by Elixir/OTP"
   - Lead with reliability story (publish reliability report)
   - Lead with Elixir/OTP technical advantage (resonates with HN audience)

2. **Elixir community** — ElixirForum, ElixirConf talks, Thinking Elixir podcast
   - "How we built a fault-tolerant workflow engine with OTP"
   - This community is hungry for production use cases

3. **Marketing Engineering blogs** — Dev.to, Medium, company blog
   - "Why your customer journey engine shouldn't be built on Node.js"
   - "WaitForEvent: The pattern that N8N can't do"
   - "How we test: Publishing reliability reports with every release"

4. **Comparison content** — SEO-driven
   - "Kalcifer vs Braze: Self-hosted alternative"
   - "Kalcifer vs Customer.io: Open-source comparison"
   - "Kalcifer vs N8N for customer journeys"

5. **Discord community** — Direct support, feature requests, contributor coordination

### Phase 2: Cloud Launch (Month 4-8)

**Goal**: 25 paying Cloud customers, $15K MRR

**Channels**:

1. **Product Hunt launch** — "Open-source Braze alternative"
2. **Self-hosted → Cloud conversion** — In-app banner: "Want zero-ops? Try Kalcifer Cloud"
3. **Integration partnerships** — SendGrid, Twilio, Segment blog features
4. **Content marketing** — Case studies from early adopters

### Phase 3: Enterprise (Month 8-12)

**Goal**: 5 Enterprise customers, $55K MRR

**Channels**:

1. **Direct outreach** — Companies using self-hosted Kalcifer at scale
2. **Partner channel** — Implementation partners / consultancies
3. **Conference presence** — SaaStr, MarTech, relevant industry events

---

## 5. Competitive Pricing Analysis

```
                    Monthly Cost for 100K Customer Profiles
                    ▼
$50,000 ┤ ████████████████████████████████  Braze
        │
$10,000 ┤ ████████████████  Iterable
        │
 $5,000 ┤ ██████████  Customer.io (scale)
        │
 $2,000 ┤ ██████  Klaviyo (at scale)
        │
 $1,000 ┤ ████  Kalcifer Cloud (Growth)
        │
   $300 ┤ ██  Kalcifer Cloud (Starter)
        │
     $0 ┤ █  Kalcifer Self-hosted (Community)
        └──────────────────────────────────────
```

**Kalcifer's pricing advantage**:
- 10-50x cheaper than Braze/Iterable
- 2-5x cheaper than Customer.io/Klaviyo
- No per-message pricing (predictable costs)
- Self-hosted option = $0 (only infrastructure cost)

---

## 6. Expansion Revenue

### 6.1 Usage-based Add-ons (Cloud)

| Add-on | Price | Description |
|--------|-------|-------------|
| Additional events | $50/1M events | Beyond plan limit |
| Additional workspaces | $50/workspace/mo | Beyond plan limit |
| Custom node hosting | $20/node/mo | Run custom code nodes |
| Data export (bulk) | $100/export | One-time bulk data export |

### 6.2 Professional Services

| Service | Price | Description |
|---------|-------|-------------|
| Implementation workshop | $2,500 | 2-day remote workshop: setup, migration, training |
| Custom integration | $5,000-20,000 | Build custom nodes for client's systems |
| Architecture review | $3,000 | Review client's deployment for optimization |
| Training (team) | $1,500/day | On-site or remote team training |

### 6.3 Marketplace (Future — Phase 5+)

Third-party developers publish custom nodes:
- Kalcifer takes 20% commission
- Developer gets 80%
- Creates ecosystem flywheel

Example marketplace nodes:
- Salesforce CRM Sync ($29/mo)
- Shopify Order Trigger ($19/mo)
- HubSpot Contact Sync ($29/mo)
- Custom ML Scoring ($49/mo)
- Slack Team Notification ($9/mo)

---

## 7. Funding Strategy

### Bootstrap Phase (Month 0-6)
- Self-funded / small angel round ($50-100K)
- Focus: Build core product, achieve 5K stars, validate demand
- Team: 2-3 people (founder + 1-2 engineers)

### Seed Round (Month 6-12)
- Target: $500K-1M
- Signal: 10K+ stars, 25+ Cloud customers, $15K+ MRR
- Focus: Cloud infrastructure, marketing, team expansion
- Team: 5-7 people

### Series A (Month 18-24)
- Target: $3-5M
- Signal: 30K+ stars, 150+ Cloud customers, $150K+ MRR
- Focus: Enterprise features, marketplace, international expansion
- Team: 15-20 people

### Comparable Exits & Valuations

| Company | Category | Last Round | Valuation | Revenue |
|---------|----------|------------|-----------|---------|
| PostHog | Open-source analytics | Series B $15M | $275M | ~$10M ARR |
| Cal.com | Open-source scheduling | Series A $25M | $200M | ~$5M ARR |
| Infisical | Open-source secrets | Series A $18M | $150M | ~$3M ARR |
| Novu | Open-source notifications | Seed $6.6M | $50M | Pre-revenue |

Kalcifer's category (Marketing Automation) has higher ACV than these comparables, suggesting strong potential.

---

## 8. Key Financial Metrics to Track

| Metric | Description | Target (Month 12) |
|--------|-------------|-------------------|
| **MRR** | Monthly Recurring Revenue | $55K |
| **ARR** | Annual Recurring Revenue | $660K |
| **NRR** | Net Revenue Retention | > 120% |
| **Gross Margin** | Revenue - COGS | > 80% |
| **CAC** | Customer Acquisition Cost | < $2,000 avg |
| **LTV:CAC** | Lifetime Value / CAC | > 5:1 |
| **Payback Period** | Months to recover CAC | < 6 months |
| **Logo Churn** | Monthly customer churn | < 3% |
| **Revenue Churn** | Monthly revenue churn | < 1% |
| **Self-hosted Installs** | Docker pulls (proxy for adoption) | 50,000 |
| **Stars** | GitHub stars (proxy for awareness) | 12,000 |
| **Contributors** | Active GitHub contributors | 50 |

---

## 9. Risks to Revenue Model

| Risk | Impact | Mitigation |
|------|--------|------------|
| AWS/GCP launches competing managed service | High | Deep integration moat, community loyalty, faster iteration |
| Competitor open-sources similar product | Medium | First-mover advantage, reliability reputation, Elixir technical moat |
| Self-hosted users never convert to Cloud | Medium | Enterprise features create separate revenue path |
| Elixir scares away potential customers | Low | Docker deployment abstracts runtime; Cloud abstracts everything |
| Open-source maintenance burden | Medium | Sustainable contributor community; prioritize Cloud/Enterprise features |

---

## 10. License Details

### Community Edition — Apache 2.0

```
Licensed under the Apache License, Version 2.0
You may use, modify, distribute, and sell Kalcifer freely.
No restriction on commercial use.
No requirement to open-source modifications.
Attribution required.
```

**Why Apache 2.0 (not AGPL/BSL/SSPL)**:
- Maximum adoption (no license fear)
- Embed-friendly (CDPs, MarTech platforms can embed)
- Builds trust (no bait-and-switch risk)
- PostHog, Supabase proved this works

### Enterprise Features — Proprietary

Enterprise-only features live in a separate, proprietary module that requires a license key. The open-source codebase has clean extension points that Enterprise features plug into without forking.

```elixir
# In open-source code:
defmodule Kalcifer.Auth do
  @behaviour Kalcifer.Auth.Strategy

  # Default: API key authentication (open-source)
  # Enterprise: SSO/SAML/OIDC (proprietary module)
  def strategy do
    Application.get_env(:kalcifer, :auth_strategy, Kalcifer.Auth.ApiKeyStrategy)
  end
end
```
