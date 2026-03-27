---
name: my-councils
description: >
  Directory of all available agent councils, teams, and specialized roles for the Kalcifer
  project. Use this skill whenever the user says "ჩემი საბჭოები", "my councils", "which
  councils", "რა საბჭოები მაქვს", "show me my teams", "list councils", "what agents do I
  have", or asks what multi-agent workflows are available. Also trigger when the user seems
  unsure which council or role to use for their task.
---

# My Agent Councils, Teams & Roles

You have **11 workflows** organized in three tiers:

## Quick Reference

### 🏛️ Councils (Multi-Agent Deliberation)

| Council | Domain | Trigger Words |
|---------|--------|---------------|
| 🏗️ **arch-council** | Architecture (Disney method) | "არქ-საბჭო", "architecture council", "system design" |
| 🏃 **sprint-team** | GitLab issue → code | "სპრინტ-გუნდი", "process issue", "dev cycle" |
| 💼 **biz-council** | Business decisions | "ბიზნეს-საბჭო", "ROI", "business decision" |
| 🎨 **ux-council** | UX deliberation | "UX საბჭო", "user experience", "design review" |
| 🏗️ **tech-council** | Tech decisions | "ტექ-საბჭო", "tech trade-offs" |
| 🧪 **qa-council** | Release readiness | "QA საბჭო", "quality review" |
| ⚙️ **devops-council** | Infrastructure | "DevOps საბჭო", "CI/CD", "infrastructure" |
| 🚀 **delivery** | MR & release | "დელივერი", "MR preparation", "release" |

### 👤 Specialist Roles (Single-Agent, Deep Focus)

| Role | Domain | Trigger Words |
|------|--------|---------------|
| 🎨 **ux-designer** | UX/UI design + prototypes | "UX დიზაინერი", "wireframe", "mockup", "prototype" |
| 💻 **coder** | Day-to-day coding | "კოდერი", "დამიწერე", "implement", "fix" |
| 🧪 **qa-engineer** | Test strategy & execution | "QA ინჟინერი", "ტესტ-გეგმა", "write tests" |

---

## Councils vs Roles — When to Use Which

**Councils** launch multiple sub-agents that debate and deliberate. Best for:
- Decisions with trade-offs that need multiple perspectives
- Architecture/design choices where you want stress-testing
- Situations where "the right answer" isn't obvious

**Specialist Roles** are single focused agents. Best for:
- Execution (writing code, writing tests, creating prototypes)
- Tasks where you know WHAT to do and need it done well
- Day-to-day work that needs consistency and discipline

### Common Workflows

| Situation | Use |
|-----------|-----|
| არქიტექტურული გადაწყვეტილება (ADR სჭირდება) | 🏗️ arch-council |
| კოდის დაწერა (feature, bugfix, refactor) | 💻 coder |
| ტესტების დაწერა ან test strategy | 🧪 qa-engineer |
| UI/UX კონცეფცია + React prototype | 🎨 ux-designer |
| GitLab issue-ს სრული pipeline-ით დამუშავება | 🏃 sprint-team |
| ბიზნეს გადაწყვეტილება | 💼 biz-council |
| ინფრასტრუქტურის ცვლილება | ⚙️ devops-council |
| კოდი მზადაა, merge/deploy გინდა | 🚀 delivery |

### Chaining Patterns

**Full product cycle:**
arch-council → ux-designer → coder → qa-engineer → delivery

**Architecture → Implementation:**
arch-council → coder → qa-engineer → delivery

**Design → Prototype → Code:**
ux-designer → coder → qa-engineer

**Quick feature:**
coder → qa-engineer → delivery

**Release prep:**
qa-engineer → delivery

---

## What's New (vs old councils)

### 🏗️ arch-council (replaces/enhances tech-council)
Disney Creative Strategy with sub-agents. Round 1 runs Dreamer/Realist/Skeptic in parallel,
then 2 cyclic rounds where each responds to the others. Produces a proper ADR with decision
matrix, risk table, and phased roadmap. The key difference: genuine dialectic tension, not
just listing pros/cons from one perspective.

### 🎨 ux-designer
Not a council — a single skeptical designer who questions everything, including your brief.
Researches before designing, generates 2-3 alternative approaches, creates interactive
React/HTML prototypes, then self-critiques the result. Output: design doc + working mockups.

### 💻 coder
Disciplined write→test→commit loop. Plans in small steps (10-50 lines per step), auto-commits
after each passing test. Never writes everything at once. Reads project skills before starting.
Uses conventional commits. Each commit = working codebase state.

### 🧪 qa-engineer
Risk-based test strategy with iterative execution. Creates a test matrix prioritized by risk
(P0/P1/P2), then implements tests iteration by iteration. After each iteration you have a
useful test suite — even if you stop early. Covers unit, integration, e2e, and property tests.

---

## All Workflows Share

- 🌐 **Web Access** — real research with WebSearch/WebFetch
- 📚 **Project Skills** — reads .claude/skills/ for project conventions
- 🔍 **Codebase Aware** — reads actual code, cites file paths and line numbers
- 📄 **Structured Output** — produces documented artifacts, not just chat responses
