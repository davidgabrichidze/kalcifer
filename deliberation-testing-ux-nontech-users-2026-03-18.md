# Deliberation Protocol: Testing / Preview / Dry-Run UX for Non-Technical Users
**Project:** Kalcifer — Elixir/OTP Flow Orchestration Engine
**Date:** 2026-03-18
**Session:** Three-agent brainstorming council (Explorer · Devil's Advocate · Synthesizer)
**Topic:** How to build testing, preview, and dry-run capabilities so non-technical users can confidently test flows before launching them.

---

## 1. Executive Summary

Non-technical operators (marketers, retailers, small-business owners) currently face a confidence gap between building a flow and launching it live — a gap that platforms like Klaviyo, Braze, and Salesforce have each addressed only partially or at enterprise price points. Kalcifer's existing architecture (NodeExecutor with injectable registries, ExecutionStep audit trail, FlowGraph static analysis, Mox already in the test stack) provides unusually strong primitives for building first-class simulation without a separate staging environment. The council converged on a three-layer strategy: (1) pre-flight static analysis that catches structural problems at draft time, (2) an in-process Safe Simulation Mode that intercepts all side effects while exercising the real execution path including `resume/3`, and (3) a plain-English audit narrative rendered from real ExecutionStep records. The hardest unsolved problem is cross-flow participant contention detection, which requires human product decisions about scope and UX before implementation begins.

---

## 2. Context & Sources

### External Research Sources
- Klaviyo Help Center — per-email preview only, no whole-flow simulation
- Braze Canvas "Preview User Paths" — full simulation but enterprise-only ($60K–$200K/yr)
- Salesforce Flow Winter '26 in-canvas debugging — developer-oriented, poor operator UX
- Shopify Flow 2025 blog — AI-generated flows, execution path preview without real data
- Zapier step-by-step testing — friendly but not holistic
- Temporal.io docs — rationale for forbidding `sleep()` in workflow definitions
- Salesforce Marketing Cloud community — no true sandbox; Pardot sandbox requires $200K+ licensing
- SHRM automation-anxiety research — 66%→89% confidence gap for non-technical operators
- HubSpot Knowledge Base — "workflow showed completed but didn't execute" false confidence case
- Callbox / Shutterfly / Adidas incident reports — real-world catastrophic mis-sends

### Kalcifer Codebase Files Referenced
- `/home/user/kalcifer/lib/kalcifer/engine/nodes/behaviour.ex` — `NodeBehaviour` callbacks: `execute/2`, `resume/3`, `validate/1`, `config_schema/0`, `category/0`
- `/home/user/kalcifer/lib/kalcifer/engine/node_executor.ex` — injectable `registry` parameter on `execute/2` and `resume/3`
- `/home/user/kalcifer/lib/kalcifer/engine/flow_server.ex` — `FlowServer` GenServer, wait scheduling via `ResumeFlowJob`, `accumulate_context/3`, `persist_waiting_state/1`
- `/home/user/kalcifer/lib/kalcifer/engine/graph_walker.ex` — `entry_nodes/1`, `next_nodes/2,3`, `find_node/2`
- `/home/user/kalcifer/lib/kalcifer/flows/flow_graph.ex` — `validate/1`: cycle detection (Kahn's), orphan BFS, branch completeness, `@branching_types`
- `/home/user/kalcifer/lib/kalcifer/engine/node_registry.ex` — ETS table, `register/2`, `lookup/1`, 23 built-in node types
- `/home/user/kalcifer/lib/kalcifer/engine/persistence/instance_store.ex` — `list_waiting_for_customer/2`, `customer_active_in_flow?/2`
- `/home/user/kalcifer/lib/kalcifer/engine/persistence/step_store.ex` — `record_step_start/3`, `record_step_complete/2`, `record_step_fail/2`
- `/home/user/kalcifer/lib/kalcifer/flows/execution_step.ex` — schema: `node_id`, `node_type`, `status`, `input`, `output`, `error`, `started_at`, `completed_at`
- `/home/user/kalcifer/lib/kalcifer/flows/flow_instance.ex` — status machine: `running → waiting → completed/failed/exited`
- `/home/user/kalcifer/lib/kalcifer/flows/flow.ex` — status machine: `draft → active ↔ paused → archived`
- `/home/user/kalcifer/lib/kalcifer/channels/channel_sender.ex` — `ChannelSender.send/3`, `ProviderRegistry.lookup/1`, creates `Delivery`, enqueues `SendMessageJob`
- `/home/user/kalcifer/lib/kalcifer/engine/nodes/action/channel/send_email.ex` — delegates to `ChannelSender.send(:email, config, context)`
- `/home/user/kalcifer/lib/kalcifer/engine/nodes/condition/frequency_cap.ex` — queries `StepStore.count_channel_steps_for_customer/3` (real DB)
- `/home/user/kalcifer/lib/kalcifer/engine/nodes/condition/condition.ex` — reads `context[field]` directly; blank values silently branch to `"false"`
- `/home/user/kalcifer/lib/kalcifer/engine/nodes/wait/wait.ex` — `execute/2` returns `{:waiting, %{duration: ...}}`; `resume/3` requires `:timer_expired` trigger
- `/home/user/kalcifer/lib/kalcifer/engine/jobs/resume_flow_job.ex` — Oban worker, `queue: :delayed_resume`, snoozes 30s if GenServer not alive
- `/home/user/kalcifer/lib/kalcifer/engine/event_router.ex` — routes events to waiting instances via `_waiting_event_type` in context
- `/home/user/kalcifer/test/support/factory.ex` — `valid_graph/0`, `branching_graph/0`, ExMachina factories for all schemas

---

## 3. Internal Deliberation Rounds

### Round 1 — Explorer Refines / Devil's Advocate Challenges / Synthesizer Identifies Threads

**Explorer (refining on DA critique):**
The DA's sharpest attack is that dry-runs that skip wait nodes miss `resume/3` bugs entirely. Agreed — but the fix is elegant in Kalcifer: because `NodeExecutor.execute/2` and `NodeExecutor.resume/2` both accept a `registry` parameter, a `SimRegistry` can map wait node types to stub modules whose `execute/2` immediately returns `{:completed, %{waited: true, simulated: true}}` rather than `{:waiting, ...}`. This preserves the full `execute → accumulate_context → next_nodes` path without inserting an Oban job or sleeping. The DA is also correct that `ChannelSender` creates real `Delivery` records and enqueues `SendMessageJob` — so a sim-mode `ChannelSender` behaviour (via `Mox`-style injection) must return `{:completed, %{simulated: true, preview: rendered_preview}}` with no side effects. The Explorer scales back "Shadow Mode" from a 24–48h real-traffic run to a per-operator opt-in because the DA correctly notes it produces false confidence when staging data diverges from production.

**Devil's Advocate (challenging the refined ideas):**
Three challenges remain unresolved after Round 1:

1. The `SimRegistry` swap approach requires `FlowServer.init/1` to accept a registry override. Currently `NodeExecutor.execute(node, context, registry \\ NodeRegistry)` defaults to the live ETS table. Running a simulation via a real `FlowServer` GenServer still writes to `InstanceStore` (PostgreSQL) and `StepStore`. If we run simulation in a real GenServer, we pollute real tables with sim data. If we run it in a separate process with a separate repo sandbox, we need test-DB-style isolation in production — which is not currently wired.

2. `FrequencyCap.execute/2` calls `StepStore.count_channel_steps_for_customer/3` against the real database. In sim mode, this will count zero (no sim steps in production tables) and always route "allowed". The simulated frequency cap result will be wrong, producing misleading branch probability data.

3. The "Blank Variable Early Warning" (static analysis on context fields) is the highest-value, lowest-implementation-cost idea — but it requires knowing which context fields the operator's real customer records actually populate. That information lives in `Customer.properties` (a `map` with arbitrary keys). Without a schema or sample, we cannot determine sparsity at graph-save time.

**Synthesizer (identifying strongest threads):**
Three strong threads emerge:

- **Static analysis (FlowGraph layer)** is already partially implemented (`FlowGraph.validate/1` does cycles, orphans, branch completeness). Extending it with config-field sparsity warnings and template-variable extraction is pure Elixir, no new infrastructure, and catches the majority of catastrophic failures before any simulation runs.
- **Sim mode as a pure function (not a GenServer)** — running the execution loop as a recursive pure function over the graph (like a fold) rather than spinning up a `FlowServer` avoids the DB-pollution problem entirely. The existing `GraphWalker` and `NodeExecutor` interfaces are already functional enough to support this.
- **ExecutionStep as the narrative source** — the schema already has `node_id`, `node_type`, `input`, `output`, `error`, `started_at`, `completed_at`. A "Why did this happen?" explainer is already 80% of the way there — it just needs a rendering layer, not new data collection.

---

### Round 2 — Explorer Addresses Gaps / Devil's Advocate Pushes Harder / Synthesizer Strengthens

**Explorer (addressing DA's Round 1 challenges):**

*Challenge 1 (DB pollution):* The solution is to build simulation as a recursive pure function — `Kalcifer.Engine.Simulator.run/3` — that takes `(graph, context, sim_opts)` and walks the graph using `NodeExecutor` with an injected `SimRegistry`. It accumulates a list of `%SimStep{}` structs (plain maps, never persisted) instead of calling `StepStore`. No GenServer is started. No DB writes occur. The function returns `{:ok, [%SimStep{}]}` or `{:error, reason, [%SimStep{}]}`. Wait node stubs immediately complete. `wait_for_event` stubs can accept a `scenario` parameter specifying which branch fires (e.g., `event_received` vs `timed_out`).

*Challenge 2 (FrequencyCap DB reads):* In `SimRegistry`, the `frequency_cap` type maps to a sim stub that reads `sim_opts[:frequency_cap_count]` (an integer the operator can set in the UI slider: "assume this customer has sent X messages recently"). This makes the frequency cap branch interactive and educational rather than silently wrong.

*Challenge 3 (blank variable sparsity):* A `FlowGraph.analyze_context_deps/1` function traverses all `condition` and action nodes, extracts referenced `config["field"]` values, and returns them as a list. A separate `Kalcifer.Customers.field_coverage/2` query can then compute, for a given tenant, what percentage of customers have a non-nil value for each referenced field. This is a lightweight aggregate query (`SELECT COUNT(*) WHERE properties->>'last_product_viewed' IS NOT NULL`) run at pre-flight time, not at graph-save time.

**Devil's Advocate (hardest remaining problems):**

*Problem A — `resume/3` path is still not exercised:* The pure-function simulator handles `execute/2` via immediate-completion stubs, but `wait_for_event` nodes have a genuine two-phase execution model: `execute/2` halts, then some external event calls `resume/3`. The sim stub that immediately returns `{:completed, ...}` from `execute/2` skips `resume/3` entirely. The `resume/3` callback is where logic like "validate the event payload" or "extract data from the event" lives. A bug in `resume/3` is completely invisible to the simulator as currently designed.

*Problem B — cross-flow participant contention is fundamentally invisible:* `InstanceStore.customer_active_in_flow?/2` checks one flow at a time. If a customer is currently waiting in Flow A (a post-purchase nurture) and the operator launches Flow B (a win-back campaign), both flows target the same customer and may send conflicting messages within hours. No existing API surface exposes this. The simulator cannot see it without querying all active instances for the simulated customer ID — and the simulated customer ID is fake, so there are no real instances to find.

*Problem C — activation UX ambiguity is a UI/product decision, not an engine decision:* The boundary between "my simulation looked good" and "I'm now sending real emails to 50,000 people" is the most dangerous moment. The engine can require `status: "draft"` before `activate_flow/1` (already enforced), but the UI can present a single "Publish" button that makes this feel instantaneous. No checklist gate exists in the current `Flows.activate_flow/1` code path.

**Synthesizer (strengthening the plan):**

The pure-function simulator is the right architectural choice and solves Problem A partially: add a second pass where, for each wait-category node encountered, the simulator calls `module.resume/3` with a synthetic trigger (`:timer_expired` for `wait`, `:event_received` for `wait_for_event` with the `event_received` branch selected). This ensures `resume/3` is exercised in the same simulation run, producing a `SimStep` with outcome. Problems B and C require product decisions before implementation — they are properly Open Questions. The DA's concern about `resume/3` is resolved architecturally; the contention and activation concerns are scoped out of the MVP.

---

### Round 3 — Final Refinement / Final Challenges / Synthesizer Produces Definitive Output

**Explorer (final refinements):**

The pre-flight analysis suite consists of three independent checks that run synchronously when the operator presses "Test Before Launch":

1. **`FlowGraph.validate/1`** (already exists) — structural: cycles, orphans, missing branch edges.
2. **`FlowGraph.analyze_config_completeness/1`** (new) — walks all nodes, calls `module.validate/1` (already defined in `NodeBehaviour`, default `:ok`), collects all config errors.
3. **`FlowGraph.analyze_context_deps/1`** (new) — extracts all context field references from condition/action configs, cross-references against `Customers.field_coverage/2` aggregate query, returns warnings like `"field 'last_product_viewed' is blank for 41% of your customers"`.

The sim mode persona system uses a `%SimPersona{}` struct containing a context map that pre-populates operator-facing fields: email, phone, properties. The UI ships with 5–7 built-in personas ("First-time visitor", "VIP with recent purchase", "Churned customer", "Customer with opted-out SMS"). Each persona is just a context map — no special engine support needed.

The audit narrative renders from `[%SimStep{}]` using a simple template: for each step, `"[Node label] — [outcome in plain English]. [Branch taken if branched]."` For `condition` nodes: `"Checked: last_product_viewed equals 'shoes'. Result: No match — 41% of customers don't have this field set."` For action nodes: `"Would send email using template 'welcome_v2'. Preview: [rendered subject line]."`.

**Devil's Advocate (final challenges):**

The three-layer approach (static analysis → simulator → narrative) is sound, but two risks remain that the team must consciously accept and not paper over:

1. **The sim stub for `ChannelSender` will render template subject lines using synthetic context data.** If the template uses `{{first_name}}` and the persona has `first_name: "Test User"`, the preview shows "Hi Test User" — which looks correct. But production customers with a blank `first_name` will receive "Hi " (blank). The static analysis layer catches this only if `analyze_context_deps/1` explicitly inspects template bodies for mustache/EEx variables. Template body inspection is not currently planned, and templates are stored externally (by `template_id`). This is a residual risk that must be documented.

2. **The `SimRegistry` architecture requires discipline.** Every new node type added to `NodeRegistry` must also have a corresponding entry in `SimRegistry`, or the simulator will fall through to `{:error, {:unknown_node_type, type}}`. This is a process/convention risk, not a technical impossibility.

**Synthesizer (definitive output):**

The council agrees on a phased, architecturally honest implementation. Phase 1 (pre-flight static analysis) ships first because it catches the majority of catastrophic failures with zero simulation complexity. Phase 2 (in-process pure-function simulator) ships second because it requires new module surface area but no infrastructure. Phase 3 (narrative rendering + persona library) ships third as a UX layer on top of Phase 2's `[%SimStep{}]` output. Phase 4 (activation gate) is a mandatory checklist enforced in `Flows.activate_flow/1` before `status_changeset("active")`. Template variable inspection is logged as a future risk to address in Phase 5 once template storage architecture is defined.

---

## 4. Key Decisions

| Decision | Rationale | Alternatives Considered | Confidence |
|---|---|---|---|
| Simulator as pure recursive function, not a FlowServer GenServer | Avoids writing sim data to production DB; no Oban jobs created; no process registry pollution; consistent with Elixir functional idioms | Separate staging DB (Salesforce SFMC model — rejected: no true sandbox, prohibitive cost); FlowServer with Ecto sandbox (rejected: production code should not depend on test infrastructure) | High |
| `SimRegistry` injected into `NodeExecutor.execute/2` (already supports this) | `NodeExecutor` already accepts `registry` as third parameter with default `NodeRegistry`; no interface changes required | Monkey-patching at the node module level (rejected: violates OTP conventions); compile-time conditional (rejected: couples test and production code) | High |
| `resume/3` exercised in second simulator pass | The DA correctly identified that skipping `resume/3` misses a whole class of bug; two-pass approach adds minimal complexity | Single-pass only (rejected: too many real bugs invisible); run a real GenServer with synthetic event injection (rejected: requires DB writes and Oban) | High |
| Pre-flight analysis runs at "Test" button press, not at graph save | Graph save is already fast and should stay so; analysis may involve DB queries (`field_coverage`) that are slow; operator expects a dedicated "test" step | Run at save (rejected: too slow, wrong mental model); run at activation (rejected: too late to be useful) | High |
| Persona library as plain context maps, no new schema | Personas are just `%{context: map()}` structs passed to the simulator; zero DB overhead; can be hardcoded in UI or stored as JSON in `Flow.entry_config` | Dedicated `personas` table (rejected: over-engineered for v1); reference to real customer records (rejected: exposes PII in test UI, production side effects) | High |
| `activate_flow/1` must pass pre-flight validation before status transition | `Flows.activate_flow/1` already gates on `no_draft_version`; adding pre-flight validation is additive and consistent | Activation gate in UI only (rejected: can be bypassed via API; enforcement must be at context layer) | Medium-High |
| Template variable blank-field risk documented but deferred | Template bodies are stored externally by `template_id`; Kalcifer does not own template rendering; inspecting templates requires API call to external system | Block activation if any template variable cannot be verified (rejected: too strict, breaks existing workflows with external templates) | Medium |

---

## 5. Open Questions (Requires Human Input)

1. **Cross-flow contention scope:** Should the simulator warn when the simulated persona is already "active" in another flow? If yes: does the pre-flight check query all active `FlowInstance` records for the test customer ID, or only instances of the same flow? What is the UX for this warning — block activation, or advisory only? This requires a product decision on multi-flow participant management.

2. **Persona library ownership:** Should built-in personas be hardcoded in the frontend, stored as tenant-specific records, or defined at the system level? Who can create custom personas — all operators, or only admins? Does custom persona creation require storing PII (real customer data) or only synthetic data?

3. **Template rendering in preview:** `send_email` nodes reference `template_id` (a string). Should the preview step make an API call to the template provider to render a preview with synthetic context? If yes, which template provider is in scope for v1? If no, should the preview show raw template metadata only?

4. **`SimRegistry` maintenance convention:** Should new node implementations be required to ship a corresponding sim stub in the same PR (enforced by a test or CI check), or is this a documentation convention only? Who owns `SimRegistry` as the node library grows?

5. **Activation gate UX:** Should `activate_flow/1` return a structured `{:error, {:pre_flight_failed, [warnings]}}` that the API surfaces as a 422, or should pre-flight be advisory (warnings shown, operator can override)? For non-technical users, a hard block may be safer; for power users, it may be frustrating.

6. **Branch probability display:** Is historical branch distribution data (e.g., "22% go to Branch A") in scope? This requires querying `ExecutionStep` records aggregated by `node_id` and `output.branch_key`. Is this analytics infrastructure (belongs in `Kalcifer.Analytics`) or pre-flight infrastructure?

7. **Shadow Mode:** Is a "run against real traffic but suppress sends" mode desired for production validation after static analysis and simulation? This requires a `mode` flag on `FlowInstance` that `ChannelSender` reads. It is architecturally feasible but has product-level implications (real participants enter the flow, which affects `FrequencyCap` counts).

---

## 6. Agreements — What All Agents Converged On

1. **No separate staging environment.** The sandbox-environment model (Salesforce Marketing Cloud, Pardot) has failed non-technical users across the industry. An in-process approach is architecturally correct and avoids the "staging data does not equal production data" false confidence trap.

2. **The execution path — including `resume/3` — must be exercised.** A simulator that only tests `execute/2` and skips wait-node resume is dangerously incomplete. The two-pass simulation design (execute pass + resume pass with synthetic triggers) is the minimum viable correctness guarantee.

3. **Failures must be visible, not suppressed.** If a node returns `{:failed, reason}` during simulation, the SimStep must record and surface the error. The narrative layer must translate `{:error, :missing_customer_id}` into "This step would fail because the customer profile has no email address." Silent green-check simulation results are worse than no simulation at all.

4. **Static analysis comes first.** `FlowGraph.validate/1` already exists. Extending it with config completeness (`validate/1` on each node module) and context dependency warnings is the highest-value, lowest-risk step. It must ship before the simulator.

5. **The activation boundary must be explicit.** The transition from `draft` to `active` (which begins sending to real participants) must require an explicit pre-flight gate in `Flows.activate_flow/1`, not just in the UI. API callers must also receive the warning.

6. **Personas should be pre-built and operator-selectable, not require API or Postman.** Non-technical users should never need to construct a JSON context payload. The 5–7 built-in personas cover the most common real-world scenarios and lower the barrier to testing below Zapier's current step-by-step approach.

7. **Frequency cap simulation must be interactive, not silently wrong.** Because `FrequencyCap.execute/2` queries real DB records (no sim steps in production tables), the sim stub must replace this with an operator-configured slider ("assume this customer has received X messages recently"). This is more useful than a silently incorrect "always allowed" result.

8. **The `ExecutionStep` schema is sufficient for narrative generation.** No new fields are needed. The `node_type`, `input`, `output`, and `error` fields already contain everything needed to render plain-English audit narratives. The rendering layer is a pure transformation function on `[%SimStep{}]`.

9. **Mox is already in the test stack** — the pattern of injecting mock modules is established. `SimRegistry` follows the same pattern. This is not a new concept for the codebase; it is an extension of an existing idiom.

---

## 7. Risks & Mitigations

| Risk | Severity | Likelihood | Mitigation |
|---|---|---|---|
| `resume/3` bugs invisible if sim only covers `execute/2` | High | High (every wait node has this exposure) | Two-pass simulation: after execute pass, run resume pass with synthetic triggers (`:timer_expired`, `:event_received`, `:timed_out`) for all wait-category SimSteps. Ship both passes together. |
| Template variable blanks cause "Hi " mis-sends in production | High | High (confirmed #1 recurring failure across platforms) | Phase 1: static analysis warns on any `condition` node referencing a field with >20% null rate. Phase 2: UI preview renders with persona data and highlights all unresolved template variables in yellow. Phase 5: inspect template bodies via provider API. |
| `SimRegistry` missing entry for new node type causes `{:error, {:unknown_node_type, type}}` in simulation | Medium | Medium (grows with node library) | Require sim stub registration as part of the node PR checklist. Add a test: `assert SimRegistry.lookup(type) != :error` for every entry in `NodeRegistry`. |
| `FrequencyCap` always returns "allowed" in simulation (no sim steps in real DB) | Medium | Certain (by design if not addressed) | Replace `FrequencyCap` in `SimRegistry` with interactive stub that reads `sim_opts[:frequency_cap_count]`. Expose slider in UI: "Customer has sent X messages in the last [window]". |
| Activation gate in `Flows.activate_flow/1` too strict, blocks power users | Low-Medium | Medium | Make pre-flight result `{:pre_flight_warnings, [warnings]}` advisory by default. Add `force: true` option to `activate_flow/1` for power-user override. Log all forced activations. |
| Cross-flow participant contention invisible in simulation | High | High (two flows targeting same customer) | Phase 1: document as known gap. Phase 3: add `Simulator.check_participant_contention/2` that queries `InstanceStore.list_waiting_for_customer/2` for the simulated customer's external_id. Surface as advisory warning, not a block. |
| Simulated `send_email` renders "Test User" but production customer has blank `first_name` | High | High | Persona library must include a "Customer with missing common fields" persona that deliberately leaves `email`, `first_name`, and `phone` blank. Simulator must surface these as warnings, not just succeed. |
| Operators interpret "simulation passed" as "flow is correct" | High | High (HubSpot false confidence case) | Narrative output must include a disclaimer: "This simulation used synthetic data. Real results will vary based on your customer profiles." Pre-flight checklist must include a step requiring operator acknowledgment of this disclaimer. |
| Shadow mode creates real `FlowInstance` records that affect `FrequencyCap` counts | Medium | High if Shadow Mode is built | Shadow Mode requires a `sim_mode: true` flag on `FlowInstance`. `FrequencyCap` must filter out sim instances. `ChannelSender` must short-circuit on `sim_mode`. This is a v2 scope item. |
| `wait_for_event` branch selection in simulation (event_received vs timed_out) is not obvious to operators | Medium | High | Persona definition UI must expose "What happens at each wait-for-event node?" as a toggle. Default to `timed_out` (pessimistic path) for first run, `event_received` for second run. |

---

## 8. Action Items

### Phase 1 — Pre-flight Static Analysis (no new infrastructure)

| Item | Description | Owner | Files Affected |
|---|---|---|---|
| P1-1 | Extend `FlowGraph.validate/1` to call `NodeRegistry.lookup(type)` for each node and return `{:error, ["unknown node type: #{type}"]}` if missing. This catches `{:error, {:unknown_node_type, type}}` at save time, not execution time. | Engine team | `lib/kalcifer/flows/flow_graph.ex`, `lib/kalcifer/engine/node_registry.ex` |
| P1-2 | Add `FlowGraph.analyze_config_completeness/1` — iterates all nodes, calls `NodeExecutor`-style lookup, then calls `module.validate/1` on each node's config, aggregates errors. | Engine team | `lib/kalcifer/flows/flow_graph.ex` |
| P1-3 | Add `FlowGraph.analyze_context_deps/1` — extracts `config["field"]` values from all `condition` nodes; returns list of field names referenced. | Engine team | `lib/kalcifer/flows/flow_graph.ex` |
| P1-4 | Add `Kalcifer.Customers.field_coverage/2` — takes `(tenant_id, [field_name])`, returns `%{field_name => coverage_percentage}` via aggregate query on `Customer.properties`. | Customers context | `lib/kalcifer/customers.ex` |
| P1-5 | Wire pre-flight analysis into `Flows.activate_flow/1` — run P1-2 + P1-3 + P1-4 before `status_changeset("active")`; return `{:pre_flight_warnings, warnings}` advisory (not blocking in v1). | Flows context | `lib/kalcifer/flows.ex` |
| P1-6 | Add API response shape for pre-flight warnings in `FlowController.activate/2`. | Web layer | `lib/kalcifer_web/controllers/flow_controller.ex` |

### Phase 2 — Pure-Function Simulator

| Item | Description | Owner | Files Affected |
|---|---|---|---|
| P2-1 | Create `Kalcifer.Engine.Simulator` module with `run/3` function signature `(graph, context, sim_opts) :: {:ok, [SimStep.t()]} | {:error, reason, [SimStep.t()]}`. Uses recursive graph-walking (mirrors `FlowServer.execute_nodes/2` logic) without GenServer or DB writes. | Engine team | `lib/kalcifer/engine/simulator.ex` (new) |
| P2-2 | Define `%SimStep{}` struct: `node_id`, `node_type`, `input`, `output`, `error`, `branch_taken`, `simulated_duration_ms`, `warnings`. | Engine team | `lib/kalcifer/engine/simulator.ex` |
| P2-3 | Create `Kalcifer.Engine.SimRegistry` GenServer mirroring `NodeRegistry` structure but with sim stubs for all 23 built-in node types. Wait stubs return `{:completed, %{waited: true, simulated: true}}`. Channel stubs return `{:completed, %{simulated: true, preview: build_preview(config, context)}}`. | Engine team | `lib/kalcifer/engine/sim_registry.ex` (new) |
| P2-4 | Implement second simulator pass: for each `SimStep` where `node_type` is in `wait` category, call `NodeExecutor.resume(node, context, synthetic_trigger, SimRegistry)` and append a `SimStep` with the resume result. `sim_opts[:wait_for_event_branches]` controls which branch fires per node. | Engine team | `lib/kalcifer/engine/simulator.ex` |
| P2-5 | Add `SimRegistry` entry requirement to the node authoring checklist/documentation. Add test: for each type in `NodeRegistry.list_all/0`, `SimRegistry.lookup(type)` must not return `:error`. | Engine team | `test/kalcifer/engine/sim_registry_coverage_test.exs` (new) |
| P2-6 | Add `POST /api/v1/flows/:id/simulate` endpoint accepting `{persona: map, sim_opts: map}`, returning `[SimStep]` as JSON. Authenticate via existing `ApiKeyAuth` plug. | Web layer | `lib/kalcifer_web/controllers/flow_controller.ex`, `lib/kalcifer_web/router.ex` |

### Phase 3 — Narrative Rendering + Persona Library

| Item | Description | Owner | Files Affected |
|---|---|---|---|
| P3-1 | Add `Kalcifer.Engine.SimNarrator.narrate/1` — takes `[SimStep.t()]`, returns `[%{node_id, headline, detail, severity}]`. `severity` is `:info | :warning | :error`. | Engine team | `lib/kalcifer/engine/sim_narrator.ex` (new) |
| P3-2 | Implement narrative templates per node category: trigger ("Flow would start when..."), condition ("Checked field X — result: branch Y taken"), wait ("Would wait 2h, then continue"), action ("Would send email using template X — preview: [subject]"), end ("Flow would complete"). | Engine team | `lib/kalcifer/engine/sim_narrator.ex` |
| P3-3 | Define built-in persona library as a module-level constant or JSON config: "First-time visitor" `%{email: "...", first_name: "Alex", properties: %{}}`, "VIP customer" `%{...purchase_count: 15, tags: ["vip"]}`, "Churned customer" `%{last_seen_at: -90_days}`, "Customer with blank fields" `%{first_name: nil, phone: nil}`, "Opted-out SMS customer" `%{preferences: %{"sms" => false}}`. Minimum 5 personas. | Product / Engine team | `lib/kalcifer/engine/sim_personas.ex` (new) |
| P3-4 | Add `Simulator.check_participant_contention/2` — takes `(tenant_id, simulated_customer_id)`, queries `InstanceStore.list_waiting_for_customer/2`. If results found, adds warning SimStep. | Engine team | `lib/kalcifer/engine/simulator.ex` |
| P3-5 | Extend narrative API response to include `narrator_output: [%{node_id, headline, detail, severity}]` alongside raw `sim_steps`. | Web layer | `lib/kalcifer_web/controllers/flow_controller.ex` |

### Phase 4 — Activation Gate

| Item | Description | Owner | Files Affected |
|---|---|---|---|
| P4-1 | Move pre-flight gate from advisory to blocking for critical errors (unknown node type, missing required config, cycles/orphans). Retain advisory for warnings (field sparsity, frequency cap). Add `force: true` opt-in for power users. | Flows context | `lib/kalcifer/flows.ex` |
| P4-2 | Add `activate_flow/2` with options parameter: `activate_flow(flow, force: false)`. | Flows context | `lib/kalcifer/flows.ex` |
| P4-3 | Add pre-activation checklist model: a list of items that must be acknowledged before `activate_flow/1` is called. Implement as validation in the web controller layer, not the context layer (product decision on exact items required). | Web layer | `lib/kalcifer_web/controllers/flow_controller.ex` |

---

## 9. Dissenting Opinions — Where Devil's Advocate Still Disagrees

**1. The two-pass simulator gives false confidence about `wait_for_event` branches.**
The second pass calls `module.resume/3` with a synthetic trigger, but the synthetic trigger is not real event data. `wait_for_event` nodes' `resume/3` implementations may inspect the trigger payload for fields like `event["order_total"]` to set context variables. The simulator will call `resume/3` with `%{}` or a stub payload that does not represent what a real event looks like. Downstream `condition` nodes will then evaluate against blank accumulated context, making the entire post-resume path unreliable. The Devil's Advocate position is that `wait_for_event` resume scenarios should be excluded from automatic simulation and instead require the operator to manually define a sample event payload in the UI. This is a harder UX ask but produces honest results. **This dissent is not resolved and should be revisited when implementing P2-4.**

**2. Field coverage queries will be slow at activation time for large tenants.**
`Customers.field_coverage/2` requires a `COUNT(*)` aggregate across potentially millions of customer records, filtered by `tenant_id`, for each referenced field. For tenants with large customer bases, this could add 500ms–2s to the activation call. The Synthesizer proposed running this at "Test" button press rather than at activation, but if pre-flight analysis is also wired into `activate_flow/1` (Phase 4), this query runs again. The Devil's Advocate position is that field coverage should be pre-computed via a periodic `Oban` maintenance job (similar to `CleanupJob` and `StatsRollupJob`) and cached — not run inline at activation. **This dissent is unresolved and should inform the Phase 4 implementation decision.**

**3. The activation gate advisory-vs-blocking split is arbitrary.**
The current proposal blocks on "critical" errors (unknown node type, cycles) and advises on warnings (field sparsity). But "41% of customers have no `last_product_viewed`" is not a warning — it is a critical error for a `condition` node that routes based on that field. A blank field causes a silent branch to `"false"` (verified in `Kalcifer.Engine.Nodes.Condition.Condition.execute/2`: `actual = context[field]`, `if actual == expected` — nil never equals the expected value). This silent false-branch is more dangerous than an unknown node type, which at least causes an explicit `{:failed}` state. The Devil's Advocate position is that field sparsity above a configurable threshold (e.g., >25% null) should be a blocking error for condition nodes. **This dissent is unresolved and requires a product decision on the threshold.**

---

## Part 2 — Executive Summary for Action

### Core Strategy

Build confidence for non-technical operators through a three-layer approach: (1) extend existing `FlowGraph.validate/1` with config completeness and context-field sparsity analysis, (2) add a pure-function in-process simulator (`Kalcifer.Engine.Simulator`) that exercises both `execute/2` and `resume/3` on every node type using an injected `SimRegistry` with no DB writes, and (3) render `[%SimStep{}]` output as a plain-English narrative with pre-built personas so operators never need to construct JSON payloads or use Postman.

### 5–7 Concrete Action Steps

1. **Extend `FlowGraph.validate/1`** to include config completeness (call `module.validate/1` on each node) and unknown-type detection via `NodeRegistry.lookup/1`. Zero new infrastructure. Highest ratio of risk-reduction to implementation effort. (P1-1, P1-2)

2. **Add `Customers.field_coverage/2`** and `FlowGraph.analyze_context_deps/1` — wire them into a pre-flight analysis call that surfaces "X% of customers are missing field Y" warnings before activation. (P1-3, P1-4, P1-5)

3. **Build `Kalcifer.Engine.Simulator.run/3`** as a pure recursive function using `SimRegistry`. Implement immediate-completion stubs for wait nodes, preview stubs for channel action nodes. Do not write to DB or start GenServer processes. (P2-1, P2-2, P2-3)

4. **Implement two-pass simulation** — execute pass followed by resume pass using synthetic triggers, so `resume/3` bugs are surfaced. Expose `sim_opts[:wait_for_event_branches]` for operator branch selection at each `wait_for_event` node. (P2-4)

5. **Add `POST /api/v1/flows/:id/simulate` endpoint** returning `{sim_steps: [...], narrator_output: [...]}`. Build `SimNarrator` to translate SimSteps into plain English. Ship with 5 built-in `SimPersonas`. (P2-6, P3-1, P3-2, P3-3, P3-5)

6. **Add `SimRegistry` coverage test** — assert every type registered in `NodeRegistry` has a corresponding entry in `SimRegistry`. Enforce in CI so new nodes cannot be merged without a sim stub. (P2-5)

7. **Move activation gate from advisory to blocking** for critical errors (unknown type, missing required config, structural graph errors). Retain advisory for warnings. Add `force: true` escape hatch for API callers who have acknowledged the risk. (P4-1, P4-2)

### Success Metrics

| Metric | Target | Measurement Method |
|---|---|---|
| Pre-flight catches graph errors before activation | 100% of known structural error types caught | Test coverage: one test per error type in `FlowGraph` |
| Simulator exercises `resume/3` for all wait node types | 100% | `SimRegistry` coverage test + simulator integration test |
| Operator can complete a full simulation without API/Postman | Yes | Usability test: non-technical user completes simulation using only UI + built-in personas |
| Activation gate blocks critical pre-flight failures | 100% | `Flows.activate_flow/1` returns `{:error, ...}` for all critical failure cases |
| Field sparsity warning surfaces before activation for condition nodes | Within 2 seconds | P99 latency of pre-flight analysis call |
| Incidents caused by blank template variables post-launch | Target: 0 after Phase 3 | Incident tracking in production |

### Key Risks and Mitigations

| Risk | Mitigation |
|---|---|
| `resume/3` bugs invisible if second pass uses empty synthetic trigger payload | Document limitation in simulator output. Block `wait_for_event` node resume simulation until operator provides sample event payload via UI. (Devil's Advocate dissent #1) |
| `SimRegistry` grows stale as new node types are added | CI-enforced coverage test: every `NodeRegistry` type must have a `SimRegistry` entry or test fails |
| Field coverage query too slow for large tenants at activation time | Pre-compute via `StatsRollupJob` on a schedule; cache result in `Flow` or `Tenant` table. Inline query only for small tenants below threshold |
| "Simulation passed" interpreted as "flow is correct" | Narrative output must include mandatory disclaimer. Pre-flight activation checklist must include explicit operator acknowledgment |
| Cross-flow participant contention invisible | Document as known gap. Add `Simulator.check_participant_contention/2` as advisory warning in Phase 3. Full enforcement requires product decision on multi-flow management |
