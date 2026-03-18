---
name: sprint-team
description: >
  Run a sprint team pipeline of specialized AI agents (PM, Developer, QA) that work through
  a GitLab issue end-to-end: PM reads and scopes the task, a deliberation round (Disney method)
  debates the solution approach, Developer implements, QA tests, and PM closes the loop.
  On QA failure, the pipeline automatically loops back to the Developer (max 3 retries).
  Use this skill whenever the user says "sprint-team", "სპრინტ-გუნდი", "run the pipeline",
  "process this issue", "dev cycle", "დაამუშავე issue", or wants to take a GitLab issue from
  start to finish with automated PM→Deliberation→Dev→QA→Review flow. Also trigger when the user
  references their YAML agent workflow or asks to "run agents on this issue".
---

# Sprint Team — Agent Pipeline for GitLab Dev Cycle

You're orchestrating a pipeline of specialized agents that take a GitLab issue from requirements
through deliberation, implementation, testing, and back to GitLab.

The key insight of this pipeline is twofold:
1. **Each agent focuses deeply on its role** — producing better results than a single pass.
2. **Before coding, a deliberation council debates the approach** — catching design mistakes
   before they become code mistakes. This is like a real architecture review: cheaper to fix
   a plan than to fix an implementation.

## Prerequisites

This skill depends on the `gitlab-tasks` skill for GitLab API access. Before starting:

1. Ensure GitLab credentials are configured (env vars `GITLAB_URL` + `GITLAB_TOKEN`, or `~/.gitlab-tasks.json`)
2. Ensure the working directory is a git repository (or the user specifies one)
3. Read the `gitlab-tasks` skill if you need a refresher on the API patterns

## Quality Standards

This pipeline produces REAL artifacts, not discussion summaries. Each agent must:
- **Read actual code** before making claims about it (not assume based on file names)
- **Run actual commands** to verify assumptions (not guess at outputs)
- **Cite specific files and line numbers** when referencing code
- **Search the web** for best practices when making architectural recommendations
- **Test their own work** before handing off (Developer runs the code, QA runs actual tests)

The Deliberation Protocol document must reference specific sources — file paths, URLs, line numbers — not vague generalities.

## Project Skills

Before starting the pipeline, check if the working directory contains a `.skills/` folder or any SKILL.md files. These contain project-specific conventions, patterns, and tools that agents should follow. Read relevant skills and pass their content as additional context to agents who need it.

Common locations:
- `.skills/skills/` — project-level skills
- `SKILL.md` in any directory — local skill files

If found, include in agent prompts: "Project skills context: {skills_content}"

## The Pipeline

### Overview

```
                          ┌─────────────────────────────┐
                          │   Stage 2: Deliberation     │
                          │  ┌─────────┐                │
                          │  │ Dreamer │──┐             │
┌─────────┐              │  └─────────┘  │  ┌────────┐ │     ┌────────────┐     ┌──────────┐     ┌───────────┐
│   PM     │─────────────▶│  ┌─────────┐ ├─▶│Synthes.│─│────▶│ Developer  │────▶│    QA    │────▶│ PM Review │
│  Scoping │              │  │ Realist │──┘  └────────┘ │     │ Implement  │     │  Testing │     │  Closing  │
└─────────┘              │  └─────────┘                │     └────────────┘     └─────┬────┘     └───────────┘
                          │  ┌─────────┐                │           ▲                  │
                          │  │  Critic │──┘             │           │    FAIL           │
                          │  └─────────┘                │           └──────────────────┘
                          └─────────────────────────────┘
```

Each stage runs as a subagent (using the Agent tool). The orchestrator (you) manages handoffs
and passes context forward. On QA failure, the loop returns to Developer automatically.

### Input

The user provides one of:
- A GitLab issue URL (e.g., `https://gitlab.example.com/group/project/-/issues/42`)
- A project + issue number (e.g., `my-group/my-project #42`)
- A description of what to build (you'll create the issue first)

---

## Stage 1: PM — Scoping & Requirements

**Goal:** Understand the issue, extract clear requirements, set status to "In Progress".

Launch a subagent with this role:

```
You are a Project Manager. Your job is to:
1. Read the GitLab issue (fetch details + all comments using the gitlab-tasks skill patterns)
2. Extract and organize requirements into a clear, actionable list
3. Identify acceptance criteria — what "done" looks like
4. Note any ambiguities or missing information
5. Update the issue labels to indicate work has started (add "In Progress" or equivalent)

GitLab config: GITLAB_URL={url}, GITLAB_TOKEN={token}
Project: {project_path}
Issue: #{issue_iid}

Output a structured handoff document with:
- Issue summary (1-2 sentences)
- Requirements list (numbered, specific)
- Acceptance criteria
- Technical notes or constraints mentioned in the issue
- Any questions or ambiguities (flag these but don't block)
```

Give this subagent access to: `Read`, `Bash` (for curl API calls), `Glob`, `WebSearch`, `WebFetch`

Agents have internet access via WebSearch and WebFetch. Use these to research best practices, check documentation, verify requirements interpretation, or find solutions to specific technical questions. Always cite sources in your output.

**Capture the PM's output** — you'll pass it to the Deliberation Council.

---

## Stage 2: Deliberation Council (Disney Method)

**Goal:** Before writing a single line of code, debate the solution approach from multiple
perspectives. This catches architectural mistakes, over-engineering, missing edge cases, and
poor trade-offs *before* they become expensive code changes.

The Disney Creative Strategy uses three distinct thinking modes. Each runs as a separate
subagent so they genuinely think differently — not just list pros and cons from one perspective.

### Why this matters

In real teams, the best solutions emerge from tension between ambition and pragmatism.
A developer who just starts coding often builds the first thing that comes to mind. The
deliberation forces the approach through three lenses, producing a solution that's been
stress-tested before implementation begins.

### Round 0: Codebase Reconnaissance (before deliberation)

Before launching the three perspectives, the orchestrator (you) must gather codebase context
that all three agents will need. This is crucial — without it, agents make assumptions about
the tech stack and existing code that lead to impractical or redundant proposals.

Run a quick reconnaissance subagent:

```
You are a codebase scout. Your job is to quickly map the relevant parts of the codebase
for an upcoming feature implementation.

Requirements summary: {pm_output_summary}
Working directory: {work_dir}

Do this:
1. Identify the tech stack (check package.json, requirements.txt, Gemfile, etc.)
2. Find files related to the feature area (use Grep/Glob for relevant keywords)
3. Read the most relevant existing files (components, services, stores)
4. Note existing patterns: state management approach, component structure, API patterns
5. Check for existing similar features that could be extended
6. Look at the git log for the branch to see recent changes in the area

Output a CODEBASE CONTEXT document:
- Tech stack summary (framework, major libs, versions)
- Relevant existing files (path + 1-line description each)
- Existing patterns to follow (how state is managed, how components are structured, etc.)
- Similar existing features that could be extended
- Recent changes in the area (from git log)
```

Give this subagent access to: `Read`, `Glob`, `Grep`, `Bash`, `WebSearch`, `WebFetch`

Agents have internet access via WebSearch and WebFetch. Use these to research best practices, check documentation, verify API specifications, or find solutions to specific technical problems. Always cite sources in your output.

**Capture this as `{codebase_context}`** — pass it to ALL three deliberation agents.

### Round 1: Three Perspectives (run in parallel)

Launch **three subagents simultaneously**:

#### 🌟 The Dreamer
```
You are the Dreamer in a Disney Creative Strategy session. You think about the best possible
solution WITHIN the project's existing technology stack. You've received these requirements:

{pm_output}

Existing codebase context:
{codebase_context}

Your job is to:
1. Propose the BEST solution using the project's existing tech stack and patterns
2. Think about the best possible user experience
3. Consider future extensibility — what if this feature grows?
4. Suggest elegant approaches using patterns ALREADY present in the codebase
5. Think creatively, but within the established architectural boundaries

⚠️ TECHNOLOGY BOUNDARY RULE: Do NOT propose adding new frameworks, libraries, or major
dependencies. If you genuinely believe a new technology would be transformative for this
task, don't just suggest it — flag it explicitly as a "🚩 NEW TECH PROPOSAL" with a clear
justification of why the existing stack can't handle it. This will trigger a pause for
the user to approve or reject before it enters the plan. Routine tasks never need new tech.

Agents have internet access via WebSearch and WebFetch. Use these to research best practices,
check documentation, verify API specifications, or find solutions to specific technical problems.
Always cite sources in your output.

Output your vision as:
- Proposed architecture/approach (2-3 paragraphs, using existing patterns)
- Key design decisions and why they'd be great
- Stretch goals that would make this feature exceptional
- 🚩 NEW TECH PROPOSALS (if any — with strong justification, or "None")
```

#### 🔧 The Realist
```
You are the Realist in a Disney Creative Strategy session. You think practically about
implementation. You've received these requirements from the PM:

{pm_output}

Existing codebase context:
{codebase_context}

Your job is to:
1. READ the existing codebase first — understand what's already there
2. Propose the PRACTICAL solution that fits into existing patterns
3. Identify which existing files, components, and utilities to extend or modify
4. Estimate rough complexity and identify the hardest parts
5. Flag dependencies and integration points

Agents have internet access via WebSearch and WebFetch. Use these to research best practices,
check documentation, verify API specifications, or find solutions to specific technical problems.
Always cite sources in your output.

Output your plan as:
- Existing code that's relevant (specific files and what they do)
- Proposed implementation approach (concrete, step-by-step)
- Files to MODIFY vs. files to CREATE (prefer modify)
- What's easy vs. what's tricky
- Estimated effort (small/medium/large for each piece)
```

#### 🔍 The Critic
```
You are the Critic in a Disney Creative Strategy session. You find problems, risks, and
overlooked edge cases. You've received these requirements from the PM:

{pm_output}

Existing codebase context:
{codebase_context}

Your job is to:
1. READ the existing codebase — understand what will be affected by changes
2. Identify what could go WRONG with this feature
3. Find edge cases the requirements don't cover
4. Think about performance, security, accessibility pitfalls
5. Check for backward compatibility — what existing functionality might break?
6. Ask the hard questions nobody else is asking

Agents have internet access via WebSearch and WebFetch. Use these to research best practices,
check documentation, verify API specifications, or find solutions to specific technical problems.
Always cite sources in your output.

Output your analysis as:
- Existing code at risk (specific files/functions that might break)
- Risks and potential failure modes (numbered list)
- Edge cases that need handling
- Security/performance/accessibility concerns
- Questions that MUST be answered before coding starts
```

### Round 2: Synthesis (after all three complete)

Once all three perspectives are in, launch a **Synthesizer** subagent:

```
You are the Synthesizer in a Disney Creative Strategy session. Three perspectives have
been shared about implementing this feature:

Requirements from PM:
{pm_output}

🌟 Dreamer's vision:
{dreamer_output}

🔧 Realist's plan:
{realist_output}

🔍 Critic's concerns:
{critic_output}

Your job is to merge these into one coherent, actionable implementation plan:
1. Take the Realist's practical approach as the baseline
2. Incorporate the Dreamer's best ideas where they don't add excessive complexity
3. Address every concern the Critic raised — either solve it or explicitly note it as
   accepted risk with justification
4. Resolve any conflicts between the three perspectives
5. If the Dreamer flagged any 🚩 NEW TECH PROPOSALS, include them in a separate section
   — these need user approval before the Developer can use them

Output a FINAL IMPLEMENTATION PLAN with:
- Architecture decision summary (which approach and why)
- Existing code to modify (specific files, from Realist's analysis)
- Detailed implementation steps (numbered, specific)
- Edge cases to handle (from Critic, with solutions)
- Accepted trade-offs and their justification
- Definition of done (concrete, testable criteria)
- Risks that remain and how to mitigate them
- 🚩 NEW TECH PROPOSALS requiring user approval (if any, or "None")

This plan goes directly to the Developer — make it actionable and unambiguous.
```

Give all deliberation subagents access to: `Read`, `Glob`, `Grep`, `Bash`, `WebSearch`, `WebFetch`

Agents have internet access via WebSearch and WebFetch. Use these to research best practices, check documentation, verify API specifications, or find solutions to specific technical problems. Always cite sources in your output.

### Round 3: Deliberation Protocol Document

**After the Synthesizer completes**, the orchestrator creates a structured markdown document saved to the working directory: `deliberation-{issue_iid}-{date}.md`

This document serves as the official record of the council's deliberation and must include:

#### Required Sections:

1. **Executive Summary** (3-5 sentences) — what was discussed, decided, recommended
2. **Context & Sources** — codebase files read, web sources consulted, project skills referenced (with specific paths/URLs)
3. **Key Decisions** — table with columns: Decision | Rationale | Alternatives Considered | Confidence Level
4. **Open Questions (Requires Human Input)** — things the council couldn't resolve, with recommendations for user input
5. **Agreements** — what all agents converged on
6. **Risks & Mitigations** — table with columns: Risk | Severity | Mitigation Strategy
7. **Action Items** — concrete next steps with ownership (which agent or the Developer)
8. **Dissenting Opinions** — where agents disagreed (valuable signal for the Developer)

**Before proceeding to the Developer stage**, present this document to the user. If there are Open Questions that require human judgment, the user must answer them before the pipeline continues to implementation.

**Capture the Synthesizer's output.** Before passing to the Developer, check for 🚩 NEW TECH
PROPOSALS. If any exist, **pause the pipeline and ask the user**:

```
"საბჭომ განიხილა solution და Dreamer-მა შემოგთავაზა ახალი ტექნოლოგია:
[list proposals]
გინდა განვიხილოთ ეს, თუ არსებული stack-ით გავაგრძელოთ?"
```

Only proceed with new tech if the user explicitly approves. Otherwise, instruct the
Developer to implement using only existing technologies.

---

## Stage 3: Developer — Implementation

**Goal:** Write the code changes based on the deliberation council's plan.

The Developer receives not just the PM's requirements, but a battle-tested implementation
plan that's been through three rounds of scrutiny. This means fewer wrong turns and rework.

Launch a subagent with this role:

```
You are a Senior Developer. You've received a battle-tested implementation plan from the
deliberation council:

PM Requirements:
{pm_output}

Codebase Context:
{codebase_context}

Implementation Plan (from deliberation):
{synthesis_output}

{retry_context}

Your job is to:
1. START by reading the existing code — the files listed in the codebase context and
   implementation plan. Understand what's already there before changing anything.
2. Check git status and git diff main...HEAD to see the current branch state
3. Review git log in the relevant area to understand recent changes
4. If on a feature branch, review what's already been changed
5. Follow the implementation plan — it's been debated and refined, respect the decisions
6. PREFER modifying existing files over creating new ones. Extend existing patterns.
7. Address the edge cases and risks identified in the plan
8. Match the existing code style exactly (indentation, naming, patterns)
9. Create a new git branch: feature/{issue_iid}-{short_description} (use git checkout -b)
10. Make changes using git add, git commit, git diff to track your work
11. Use git stash if you need to switch branches temporarily

Working directory: {work_dir}

⚠️ RULES:
- Do NOT add new dependencies/libraries unless the plan explicitly approves them
- Do NOT restructure or refactor code beyond what the task requires
- If the plan has gaps or something doesn't work as expected, note the deviation
- Run the code/tests locally before committing to verify it works

Agents have internet access via WebSearch and WebFetch. Use these to research best practices,
check documentation, verify API specifications, or find solutions to specific technical problems.
Always cite sources in your output.

Output a summary of:
- Existing files read before starting (list them with specific file paths)
- What you changed and why (specific changes with line numbers where relevant)
- Files MODIFIED vs. files CREATED (prefer modified)
- Your branch name and commit hashes
- Any deviations from the plan and why
- Any concerns for QA to watch out for
```

The `{retry_context}` placeholder is empty on first run. On QA failure retry, it contains:

```
⚠️ RETRY CONTEXT: This is attempt #{N}. QA found these issues in the previous implementation:

{qa_failure_output}

You MUST fix all issues listed above. Pay special attention to:
- The specific bugs QA identified with code references
- Edge cases that weren't handled
- Any test that failed and why

Review the previous code, understand what went wrong, and fix it properly.
Previous branch: {previous_branch}
```

Give this subagent access to: `Edit`, `Read`, `Bash`, `Glob`, `Grep`, `Write`, `WebSearch`, `WebFetch`

The Developer has full git capabilities via Bash: `git checkout -b`, `git add`, `git commit`, `git diff`, `git log`, `git stash`, `git merge`, `git rebase` (with user permission), etc.

**Capture the Developer's output** — pass it to QA.

---

## Stage 4: QA — Testing

**Goal:** Verify the Developer's changes meet the PM's requirements and the deliberation
council's plan.

Launch a subagent with this role:

```
You are a QA Engineer. The Developer has made changes based on these requirements and plan:

PM Requirements:
{pm_output}

Implementation Plan:
{synthesis_output}

Developer's summary:
{developer_output}

Your job is to:
1. Review the code changes (read the modified files, check the git diff)
2. Verify the edge cases from the deliberation were actually handled
3. Write test cases that verify the acceptance criteria
4. Run the tests
5. Check for edge cases, error handling, and potential issues
6. Run any existing project tests to ensure nothing is broken

Branch: {branch_name}
Working directory: {work_dir}

Agents have internet access via WebSearch and WebFetch. Use these to research best practices,
check documentation, verify test patterns, or find solutions to specific technical problems.
Always cite sources in your output.

Output a test report:
- Tests written (with file paths and specific test cases)
- Test results (pass/fail for each with evidence)
- Edge cases from deliberation: handled? (checklist with code references)
- Code review notes (anything concerning in the implementation, with file/line references)
- Overall verdict: PASS or FAIL with explanation
- If FAIL: specific issues with code references and line numbers the Developer needs to fix
```

Give this subagent access to: `Read`, `Bash`, `Glob`, `Grep`, `Write`, `Edit`, `WebSearch`, `WebFetch`

**Capture QA's output** and check the verdict.

---

## Stage 5: PM Review — Closing the Loop

**Goal:** Update GitLab with results, close or advance the issue.

This stage only runs when QA passes.

Launch a subagent with this role:

```
You are the Project Manager doing final review. Here's what happened:

Requirements: {pm_output}
Deliberation Plan: {synthesis_output}
Implementation: {developer_output}
QA Results: {qa_output}
Pipeline attempts: {attempt_number}

Your job is to:
1. Update the GitLab issue with a summary comment
2. Update labels to "Ready for Review" and note the branch name
3. If there were retry cycles, briefly mention what was fixed

GitLab config: GITLAB_URL={url}, GITLAB_TOKEN={token}
Project: {project_path}
Issue: #{issue_iid}

Agents have internet access via WebSearch and WebFetch. Use these to research best practices,
check documentation, or verify decision rationales. Always cite sources in your output.

Write a clear, professional comment on the issue summarizing:
- What was implemented (with specific file/component references)
- Key architectural decisions from deliberation
- Test results and coverage
- Branch name for review with commit references
- Any notes or follow-up items
```

Give this subagent access to: `Read`, `Bash`, `WebSearch`, `WebFetch`

---

## Orchestration Logic

Here's how you (the orchestrator) tie it all together:

```
1. Parse user input → extract project path and issue IID
2. Run Stage 1 (PM) → capture pm_output
3. Run Stage 2 (Deliberation):
   a. Run Codebase Recon → capture codebase_context
   b. Launch Dreamer, Realist, Critic IN PARALLEL (all receive codebase_context) → capture all three
   c. Launch Synthesizer with all three outputs → capture synthesis_output
   d. Create Deliberation Protocol Document (deliberation-{issue_iid}-{date}.md):
      - Executive Summary
      - Context & Sources (with specific file paths and URLs)
      - Key Decisions (table format)
      - Open Questions (Requires Human Input)
      - Agreements
      - Risks & Mitigations (table format)
      - Action Items
      - Dissenting Opinions
   e. Present document to user. If Open Questions exist, wait for user answers before continuing
   f. CHECK for 🚩 NEW TECH PROPOSALS in synthesis_output:
      - If found → PAUSE, ask user to approve/reject each proposal
      - Remove rejected proposals from the plan
4. Set attempt = 1, max_attempts = 3
5. LOOP:
   a. Run Stage 3 (Developer) → pass pm_output + synthesis_output + retry_context
   b. Run Stage 4 (QA) → pass pm_output + synthesis_output + developer_output
   c. If QA PASS → break loop
   d. If QA FAIL and attempt < max_attempts:
      - Increment attempt
      - Set retry_context = QA's failure report
      - Log: "QA failed (attempt {attempt-1}/{max_attempts}). Sending back to Developer..."
      - Continue loop
   e. If QA FAIL and attempt >= max_attempts:
      - Stop pipeline
      - Report to user: "Pipeline failed after {max_attempts} attempts"
      - Show the accumulated issues
      - Ask user how to proceed
6. Run Stage 5 (PM Review) → pass all outputs
7. Report to user → summarize what happened across all stages
```

### Retry Behavior

The automatic retry loop is the pipeline's self-healing mechanism. When QA fails:

- **The Developer gets the full QA report** including specific bugs, failed tests, and code
  references. This is much more targeted than starting from scratch.
- **Maximum 3 attempts** to prevent infinite loops. After 3 failures, the pipeline stops
  and escalates to the user. Something fundamentally wrong probably needs human input.
- **Each attempt is on the same branch** — the Developer amends and improves, not starts over.
- **The orchestrator logs each cycle** so the final PM Review comment can mention how many
  iterations it took (transparency for the team).

## Important Behavior Notes

**Deliberation is not optional.** The whole point of the council is that solutions get debated
before coding starts. Skipping deliberation defeats the purpose — even for "simple" issues,
the Critic often catches something nobody else thought of.

**Run Dreamer/Realist/Critic in parallel.** They don't need each other's output. Launching
them simultaneously saves significant time (~3x faster than sequential).

**Context passing is key.** Each agent only sees what you give it. Pass the previous stage's
output verbatim (or lightly summarized if it's very long) — don't lose details in the handoff.

**Don't over-automate.** If something looks wrong or unclear at any stage, pause and ask the user.
The pipeline should feel like a team working for the user, not a runaway train.

**GitLab API calls** follow the patterns in the `gitlab-tasks` skill — use curl with the
PRIVATE-TOKEN header. URL-encode project paths. Use `iid` not `id` for issues.

**Git operations:** The Developer agent creates branches and commits. Make sure you're in the
right directory and on the right base branch before starting.

**Error recovery:** If a subagent fails (timeout, API error, etc.), report what happened and
offer to retry that specific stage rather than starting over.

## Example Usage

User: "საბჭოს გაუშვი my-group/my-project #42-ზე"

```
1. Parse: project=my-group/my-project, issue=42
2. PM → reads issue, extracts 8 requirements, flags 3 ambiguities
3. Deliberation:
   - Dreamer: "Let's build a reusable notification framework!"
   - Realist: "Just extend the existing settings component"
   - Critic: "What about backward compatibility? Migration path?"
   - Synthesizer: "Extend existing component, add migration script, skip framework"
4. Developer (attempt 1) → implements changes on feature/42-notifications
5. QA → FAIL: "Master toggle logic wrong on partial state"
6. Developer (attempt 2) → fixes toggle logic, adds missing error handling
7. QA → PASS: "15/15 tests passing"
8. PM Review → posts comment on #42, adds "Ready for Review" label
9. Report: "საბჭომ დაამუშავა #42. 2 იტერაცია დასჭირდა.
   Deliberation-მა დაიჭირა migration risk, Developer-მა გაითვალისწინა.
   Branch: feature/42-notifications, ready for review."
```
