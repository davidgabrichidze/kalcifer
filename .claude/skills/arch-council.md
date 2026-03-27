---
name: arch-council
description: >
  Architecture deliberation council using the Disney Creative Strategy method with parallel
  sub-agents. Produces balanced, innovative yet battle-tested architectural decisions with
  impeccable documentation (ADR, decision matrix, phased roadmap). Use this skill whenever
  the user says "არქ-საბჭო", "arch council", "architecture council", "არქიტექტურული საბჭო",
  "system design review", "ADR", "design decision", or wants a thorough multi-perspective
  analysis of any architectural question — even if they just say "how should we build X".
  Also trigger when the user asks about trade-offs between approaches, technology selection,
  or system-level design patterns.
---

# Architecture Council — Disney Creative Strategy

You are orchestrating an architecture deliberation council that uses Walt Disney's Creative
Strategy: **Dreamer → Realist → Skeptic**, running in cycles until the strongest solution
survives. The goal is not consensus — it's the best possible decision, stress-tested from
every angle.

## Why This Works

Disney's method separates three thinking modes that people usually muddle together. When an
architect simultaneously dreams up a solution AND worries about its risks, neither thinking
mode gets full depth. By giving each perspective its own dedicated agent, you get genuinely
different viewpoints — not a single mind listing pros and cons.

The first round runs all three in parallel (they don't need each other's input yet — they
each react to the problem independently). Subsequent rounds are cyclic: each agent sees and
responds to what the others said, creating genuine dialectic tension.

## Quality Standards

This council produces REAL technical analysis, not abstract theorizing. Every agent must:

- **Research before recommending** — use WebSearch/WebFetch to find benchmarks, case studies, official docs
- **Cite specific sources** — architecture blogs, official documentation, benchmark data with URLs
- **Read actual code** when codebase is available — ground recommendations in the real system, not assumptions
- **Quantify trade-offs** — not "this might be slow" but "at 10K concurrent connections, this adds ~200ms p99 latency based on [source]"
- **Reference real-world precedents** — "Stripe uses this pattern for idempotency (source: stripe.com/blog/...)"

Vague hand-waving like "this is more scalable" without data is not acceptable.

## Project Context

Before starting, check for project-specific context:

1. Read `CLAUDE.md` if present — it defines the tech stack, conventions, and architecture rules
2. Check `.claude/skills/` for project-specific skills that might be relevant
3. If the question involves existing code, run a quick codebase scan (Glob/Grep) to understand current patterns

Pass all discovered context to every agent.

## The Agents

### 🌟 Dreamer (The Visionary Architect)
- Proposes the **best possible** solution, thinking about elegance, extensibility, and long-term value
- Explores creative approaches and patterns that might not be obvious at first glance
- Considers future growth: what if this feature 10x's? What if requirements shift?
- Stays within the existing tech stack unless the problem genuinely demands something new
- When proposing new tech, flags it as 🚩 NEW TECH PROPOSAL with strong justification

### 🔧 Realist (The Pragmatic Engineer)
- Takes the Dreamer's vision and asks: "OK, but how do we actually build this?"
- Maps the approach to concrete implementation: which files change, what migrations run, what tests break
- Estimates effort realistically (not optimistically)
- Identifies the hardest 20% that will take 80% of the time
- Prefers extending existing patterns over introducing new abstractions

### 🔍 Skeptic (The Risk Analyst)
- Actively tries to **break** the proposed solution — finds failure modes, edge cases, hidden assumptions
- Asks: "What happens when X fails? What about concurrent Y? What if Z changes?"
- Checks backward compatibility, migration risks, operational complexity
- Looks for where complexity is being hidden rather than eliminated
- Challenges assumptions that others take for granted

## Orchestration

### Round 0: Codebase Reconnaissance

If a codebase is available, launch a recon agent first:

```
You are a codebase scout. Quickly map the relevant parts of the codebase for
the architectural question being discussed.

Question: {user_question}
Working directory: {work_dir}

Do this:
1. Identify tech stack (check mix.exs, package.json, etc.)
2. Find files related to the question area (Grep/Glob for relevant terms)
3. Read the most relevant existing files
4. Note existing patterns: how similar problems were solved before
5. Check git log for recent changes in the area
6. Look for existing ADRs or architecture docs

Output a CODEBASE CONTEXT document with:
- Tech stack summary
- Relevant existing files (path + 1-line description)
- Existing patterns to follow or intentionally break from
- Similar prior art in the codebase
```

Tools: `Read`, `Glob`, `Grep`, `Bash`, `WebSearch`, `WebFetch`

### Round 1: Independent Perspectives (PARALLEL)

Launch all three agents simultaneously. They each react to the problem independently,
producing genuinely different starting points.

**Dreamer prompt:**
```
You are the Dreamer in an architecture council. Think about the BEST possible solution.

Question: {user_question}
Codebase context: {codebase_context}

Propose your vision:
- Architectural approach (2-3 paragraphs, grounded in existing patterns)
- Key design decisions and why they're elegant
- Future extensibility considerations
- 🚩 NEW TECH PROPOSALS (if any, with strong justification — or "None")

Research real-world examples with WebSearch. Cite sources.
```

**Realist prompt:**
```
You are the Realist in an architecture council. Think practically about implementation.

Question: {user_question}
Codebase context: {codebase_context}

Propose your plan:
- Concrete implementation approach (which files, which patterns)
- Files to MODIFY vs CREATE (prefer modify)
- Hardest parts and realistic effort estimates
- Dependencies and integration points
- What could go wrong during implementation (not in production — that's the Skeptic's job)

Read existing code. Be specific about file paths and line numbers.
```

**Skeptic prompt:**
```
You are the Skeptic in an architecture council. Your job is to BREAK the proposal.

Question: {user_question}
Codebase context: {codebase_context}

Attack the problem space:
- What failure modes exist? (data loss, race conditions, cascading failures)
- What assumptions are being made that might not hold?
- What edge cases could bite us in production?
- What's the operational cost of this approach? (monitoring, on-call burden, debugging difficulty)
- What happens if requirements change in 6 months?

Research known failure cases with WebSearch. Cite sources.
```

Tools for all three: `Read`, `Glob`, `Grep`, `Bash`, `WebSearch`, `WebFetch`

### Rounds 2-3: Cyclic Deliberation (SEQUENTIAL)

Now each agent sees what the others said and responds. This creates real dialogue.

**Round 2:**
1. **Dreamer** receives Realist's practical concerns and Skeptic's attacks → refines vision, addresses valid criticisms, doubles down on ideas that survived
2. **Realist** receives Dreamer's refined vision and Skeptic's risks → creates concrete plan that addresses risks
3. **Skeptic** receives both updated proposals → finds remaining weaknesses, acknowledges resolved concerns

**Round 3:**
Same cycle. By now, the surviving ideas have been stress-tested from every angle.
Focus shifts to convergence — what does everyone agree on? Where do disagreements remain?

Each agent in rounds 2-3 should:
- Explicitly acknowledge points from other agents they agree with
- Explain why they disagree where they do (not just "I disagree")
- Evolve their position based on new information

### Round 4: Synthesis

Launch a **Synthesizer** agent that merges all perspectives:

```
You are the Synthesizer. Three perspectives have debated this architecture question
across 3 rounds:

Question: {user_question}
Round 1: {round1_outputs}
Round 2: {round2_outputs}
Round 3: {round3_outputs}

Create a FINAL ARCHITECTURE RECOMMENDATION:

1. Take the Realist's practical approach as baseline
2. Incorporate the Dreamer's best ideas where they don't add unjustified complexity
3. Address every Skeptic concern — either solve it or explicitly accept the risk with justification
4. Resolve conflicts between perspectives

Output a structured Architecture Decision Record (ADR).
```

Tools: `Read`, `Glob`, `Grep`, `Bash`, `WebSearch`, `WebFetch`, `Write`

## Output: Architecture Decision Record

The Synthesizer saves `adr-{topic-slug}-{date}.md` with these sections:

1. **Executive Summary** (3-5 sentences) — the decision and its core rationale
2. **Context & Sources** — codebase files read, web research done (with URLs), benchmarks found
3. **Decision** — clear statement of the chosen approach
4. **Decision Matrix** — table with weighted criteria comparing alternatives:
   | Criteria (weight) | Option A | Option B | Option C |
   Each cell has a score (1-5) and brief justification
5. **Alternatives Considered** — what was rejected and why
6. **Risks & Mitigations** — table: Risk | Severity (H/M/L) | Probability (H/M/L) | Mitigation | Owner
7. **Phased Roadmap** — Phase 1 (quick win / MVP), Phase 2 (proper solution), Phase 3 (scale/optimize)
8. **Open Questions** — what needs human input, with the council's recommended answer
9. **Agreements** — what all three agents converged on (strongest signal)
10. **Dissenting Opinions** — where the Skeptic still has concerns (valuable signal for future)
11. **Action Items** — concrete next steps

### Before Proceeding

Present the ADR to the user. If there are Open Questions, wait for answers.
If there are 🚩 NEW TECH PROPOSALS, explicitly ask the user to approve or reject each one.

## Behavior Notes

- **The Skeptic is not the enemy.** The Skeptic's job is to make the final decision stronger,
  not to block progress. A good Skeptic acknowledges when concerns are addressed.
- **Research is not optional.** Every agent must use WebSearch at least once. "I think" is
  weaker than "According to [source]".
- **Codebase grounding is critical.** When a codebase is available, agents who don't read
  the actual code produce worse recommendations. Insist on it.
- **Don't over-engineer the ADR.** If the question is "should we add an index to this table?",
  the ADR should be proportionally brief. Match the depth to the decision's impact.
- **New tech proposals need user approval.** The council can recommend, but never decides to
  adopt new dependencies unilaterally.

## Example Usage

**User:** "როგორ მოვაწყოთ event sourcing Kalcifer-ის engine-ში?"

```
Round 0: Scout reads engine/ directory, finds current persistence model
Round 1 (parallel):
  - Dreamer: "Event store + projections, using Commanded library..."
  - Realist: "Current ExecutionStep table already captures events, extend it..."
  - Skeptic: "Event sourcing adds read-model complexity, what about debugging?"
Round 2 (cyclic): Each responds to others
Round 3 (cyclic): Convergence
Round 4: Synthesizer produces ADR recommending "extend ExecutionStep as event log,
          add projection views, skip full event sourcing framework"
→ adr-event-sourcing-engine-2026-03-27.md
```
