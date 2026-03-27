# Kalcifer — QA Master Test Plan

**Version**: 1.0 \
**Author**: Lead Automated QA Engineer \
**Date**: 2026-03-27 \
**Status**: Active — სრული სატესტო გეგმა ყველა დომეინისთვის \

---

## 1. მიმოხილვა

### 1.1 პროექტის აღწერა

Kalcifer არის Flow ორკესტრაციის ძრავა, აშენებული Elixir/OTP-ზე. სისტემა შედგება შემდეგი ძირითადი ფენებისგან:

- **Core Engine** — Flow-ების შესრულების ძრავი (GenServer-per-instance, graph traversal, node execution)
- **Domain Contexts** — Flows, Marketing, Tenants, Customers, Channels, Analytics, Audit, Accounts
- **Node System** — 24+ plugin-სტილის node, 5 კატეგორიაში (trigger, action, condition, wait, end)
- **Persistence Layer** — InstanceStore, StepStore, Ecto schemas
- **API Layer** — Phoenix REST API, WebSocket channels, plugs
- **AI Subsystem** — Chat, Tools, Context/Memory, Agent flows, Council routing
- **Versioning** — Live migration, rollback, node mapping

### 1.2 არსებული მდგომარეობა

| მეტრიკა | მნიშვნელობა |
|----------|-------------|
| არსებული ტესტ ფაილები | 88 |
| არსებული test case-ები | 861 |
| Bug regression ტესტები | 21 |
| Integration ტესტები | 2 ფაილი |
| Property ტესტები | 1 ფაილი (node_mapper) |
| Chaos/Load ტესტები | 0 |
| E2E ტესტები | 0 |

### 1.3 დომეინების რუკა

```
┌─────────────────────────────────────────────────────────────────┐
│                         API Layer                               │
│  Controllers · Plugs · WebSocket · Router                       │
├──────────┬──────────┬──────────┬──────────┬─────────┬──────────┤
│  Flows   │Marketing │Customers │ Channels │Analytics│   AI     │
│  Context │ Context  │ Context  │ Context  │ Context │Subsystem │
├──────────┴──────────┴──────────┴──────────┴─────────┴──────────┤
│                      Engine Core                                │
│  FlowServer · NodeExecutor · GraphWalker · EventRouter          │
│  RecoveryManager · CircuitBreaker · FlowTrigger                 │
├─────────────────────────────────────────────────────────────────┤
│                      Node System                                │
│  Trigger(3) · Action/Channel(6) · Action/Data(5) · Action/AI(6)│
│  Condition(5) · Wait(3) · End(2) · Orchestration(2)            │
├─────────────────────────────────────────────────────────────────┤
│                   Persistence & Jobs                            │
│  InstanceStore · StepStore · ResumeFlowJob · CleanupJob         │
├─────────────────────────────────────────────────────────────────┤
│                   Versioning                                    │
│  Migrator · NodeMapper                                          │
├─────────────────────────────────────────────────────────────────┤
│                   Infrastructure                                │
│  Tenants · Audit · Accounts · Supervision Tree                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. დომეინი #1: Flows Context

**მოდული**: `Kalcifer.Flows`
**სქემები**: `Flow`, `FlowVersion`, `FlowInstance`, `ExecutionStep`, `FlowGraph`

### 2.1 Unit Tests

#### TC-FLOW-U001: Flow CRUD

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | create_flow — ვალიდური ატრიბუტები | `%{name: "Test", description: "desc"}` | `{:ok, %Flow{status: "draft"}}` | P0 |
| U001.2 | create_flow — ცარიელი სახელი | `%{name: ""}` | `{:error, changeset}` name required | P0 |
| U001.3 | create_flow — tenant_id გარეშე | `%{name: "Test"}`, nil tenant | `{:error, changeset}` | P0 |
| U001.4 | get_flow — არსებული | valid UUID | `%Flow{}` | P0 |
| U001.5 | get_flow — არარსებული | random UUID | `nil` | P0 |
| U001.6 | list_flows — tenant isolation | tenant_a, tenant_b | მხოლოდ tenant_a-ს flows | P0 |
| U001.7 | list_flows — status filter | `status: "active"` | მხოლოდ active flows | P1 |
| U001.8 | list_flows — ცარიელი შედეგი | new tenant | `[]` | P1 |
| U001.9 | update_flow — draft-ზე | `%{name: "New"}` | `{:ok, updated}` | P0 |
| U001.10 | update_flow — active flow-ზე | `%{name: "New"}` | `{:error, _}` ან name only fields | P1 |
| U001.11 | delete_flow — draft | draft flow | `{:ok, deleted}` | P0 |
| U001.12 | delete_flow — active | active flow | `{:error, _}` | P0 |

#### TC-FLOW-U002: Flow Lifecycle State Machine

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | draft → active (activate_flow) | draft flow + published version | `{:ok, flow}` status="active" | P0 |
| U002.2 | activate_flow — ვერსიის გარეშე | draft flow, no published version | `{:error, _}` | P0 |
| U002.3 | active → paused (pause_flow) | active flow | `{:ok, flow}` status="paused" | P0 |
| U002.4 | paused → active (resume_flow) | paused flow | `{:ok, flow}` status="active" | P0 |
| U002.5 | active → archived (archive_flow) | active flow | `{:ok, flow}` status="archived" | P0 |
| U002.6 | paused → archived | paused flow | `{:ok, flow}` status="archived" | P0 |
| U002.7 | draft → paused (invalid) | draft flow | `{:error, _}` | P0 |
| U002.8 | archived → active (invalid) | archived flow | `{:error, _}` | P0 |
| U002.9 | archived → archived (idempotent?) | archived flow | `{:error, _}` | P1 |
| U002.10 | draft → archived (valid shortcut) | draft flow | `{:ok, _}` | P1 |

#### TC-FLOW-U003: Flow Version Management

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | create_version — ვალიდური graph | valid graph JSON | `{:ok, %FlowVersion{status: "draft"}}` | P0 |
| U003.2 | create_version — ინვალიდური graph | graph with cycle | `{:error, _}` | P0 |
| U003.3 | create_version — auto increment version_number | flow with v1 | version_number == 2 | P0 |
| U003.4 | publish_version — draft → published | draft version | `{:ok, %{status: "published"}}` | P0 |
| U003.5 | publish_version — already published | published version | `{:error, _}` | P1 |
| U003.6 | list_versions — ordering | flow with 3 versions | ordered by version_number | P1 |
| U003.7 | get_version — by flow_id + version_number | valid pair | `%FlowVersion{}` | P0 |
| U003.8 | deprecate old version on new publish | v1 published, publish v2 | v1 status="deprecated" | P1 |

#### TC-FLOW-U004: Flow Migration & Rollback

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U004.1 | migrate_flow_version — migrate_all strategy | active flow, new version | running instances migrated | P0 |
| U004.2 | migrate_flow_version — new_entries_only | active flow, new version | existing stay, new use v2 | P0 |
| U004.3 | migrate — same version (rejected) | v1 → v1 | `{:error, _}` | P0 |
| U004.4 | migrate — invalid strategy | "invalid_strategy" | `{:error, _}` | P0 |
| U004.5 | rollback_flow_version — valid target | v2 → v1 | instances rolled back | P0 |
| U004.6 | rollback — invalid target version | v2 → v99 | `{:error, _}` | P0 |
| U004.7 | migration_status — mixed versions | instances on v1 + v2 | `%{1 => n, 2 => m}` | P1 |

#### TC-FLOW-U005: FlowGraph Validation

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U005.1 | validate — valid DAG | simple linear graph | `:ok` | P0 |
| U005.2 | validate — graph with cycle | A→B→C→A | `{:error, [cycle]}` | P0 |
| U005.3 | validate — orphan node | disconnected node | `{:error, [unreachable]}` | P0 |
| U005.4 | validate — missing trigger node | no entry point | `{:error, _}` | P0 |
| U005.5 | validate — missing end node | no exit point | `{:error, _}` | P1 |
| U005.6 | validate — duplicate node IDs | two nodes with same id | `{:error, _}` | P0 |
| U005.7 | validate — empty graph | `%{"nodes" => [], "edges" => []}` | `{:error, _}` | P1 |
| U005.8 | validate — edge to nonexistent node | edge target doesn't exist | `{:error, _}` | P0 |
| U005.9 | validate — branch completeness | condition with only "true" branch | `{:error, _}` | P1 |
| U005.10 | validate — complex branching graph | multiple conditions + merges | `:ok` | P1 |

### 2.2 Integration Tests

| ID | Test Case | Description | Priority |
|----|-----------|-------------|----------|
| I-FLOW-001 | Full flow lifecycle DB round-trip | create → publish version → activate → pause → resume → archive; verify all DB states | P0 |
| I-FLOW-002 | Version cascade on activate | activating flow sets active_version_id, deprecates old | P0 |
| I-FLOW-003 | Concurrent flow creation same tenant | 10 parallel create_flow calls | P1 |
| I-FLOW-004 | Flow deletion cascades | delete draft flow → versions cleaned up | P1 |
| I-FLOW-005 | Migration with running instances DB | migrate 100 instances, verify DB status consistency | P0 |

---

## 3. დომეინი #2: Engine Core

**მოდულები**: `FlowServer`, `NodeExecutor`, `GraphWalker`, `EventRouter`, `RecoveryManager`, `FlowTrigger`, `CircuitBreaker`, `EventBroadcaster`

### 3.1 Unit Tests

#### TC-ENGINE-U001: FlowServer

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | start_link — ვალიდური config | flow_id, customer_id, graph | `{:ok, pid}`, state == running | P0 |
| U001.2 | start_link — missing flow_id | incomplete config | `{:error, _}` | P0 |
| U001.3 | execute — linear flow to completion | entry → action → exit | state == completed | P0 |
| U001.4 | execute — branching flow (true path) | condition evaluates true | correct branch followed | P0 |
| U001.5 | execute — branching flow (false path) | condition evaluates false | correct branch followed | P0 |
| U001.6 | execute — wait node pauses execution | wait node in graph | state == waiting | P0 |
| U001.7 | resume — after wait completion | waiting state + resume signal | execution continues | P0 |
| U001.8 | resume — after event received | waiting_for_event + matching event | execution continues | P0 |
| U001.9 | execute — node failure handling | node returns {:failed, reason} | step recorded as failed | P0 |
| U001.10 | execute — context accumulation | multi-node flow | each node result in context.accumulated | P0 |
| U001.11 | get_state — running instance | active pid | current state struct | P0 |
| U001.12 | cancel — running instance | active pid | state == exited | P1 |
| U001.13 | migrate — version change | new graph, node_mapping | graph updated, execution continues | P1 |
| U001.14 | dry_run mode | context._dry_run == true | no side effects, simulated results | P0 |
| U001.15 | parallel node execution | parallel_group node | all branches execute concurrently | P1 |

#### TC-ENGINE-U002: NodeExecutor

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | execute — delegates to correct module | node type "send_email" | SendEmail.execute/2 called | P0 |
| U002.2 | execute — unregistered node type | "unknown_type" | `{:error, :unknown_node_type}` | P0 |
| U002.3 | execute — node raises exception | module raises RuntimeError | `{:failed, wrapped_error}` | P0 |
| U002.4 | execute — node timeout | module hangs | `{:failed, :timeout}` | P1 |
| U002.5 | resume — delegates resume/3 | wait node with resume callback | resume/3 called | P0 |
| U002.6 | resume — node without resume callback | action node | `{:error, :not_resumable}` | P1 |

#### TC-ENGINE-U003: GraphWalker

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | entry_nodes — single trigger | graph with 1 trigger | `["trigger_1"]` | P0 |
| U003.2 | entry_nodes — multiple triggers | graph with 3 triggers | all 3 trigger IDs | P1 |
| U003.3 | find_node — existing | valid node_id | `%{id: ..., type: ..., config: ...}` | P0 |
| U003.4 | find_node — nonexistent | invalid node_id | `nil` | P0 |
| U003.5 | next_nodes — linear | node with 1 outgoing edge | `[next_node]` | P0 |
| U003.6 | next_nodes — branching | condition node + branch_key="true" | correct branch target | P0 |
| U003.7 | next_nodes — end node | exit node | `[]` | P0 |
| U003.8 | next_nodes — no matching branch | branch_key="unknown" | `[]` | P1 |
| U003.9 | outgoing_edges — fan out | node with 3 outgoing | all 3 edges | P1 |

#### TC-ENGINE-U004: EventRouter

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U004.1 | route_event — matching wait | customer_id + event_type match | event delivered to instance | P0 |
| U004.2 | route_event — no matching wait | unregistered customer_id | silently ignored, no crash | P0 |
| U004.3 | route_event — multiple waits same customer | 2 instances waiting for same customer | both receive event | P1 |
| U004.4 | route_event — different event type | registered for "purchase", send "pageview" | not delivered | P0 |
| U004.5 | route_event — cross-tenant isolation | tenant_a event, tenant_b instance | not delivered | P0 |

#### TC-ENGINE-U005: RecoveryManager

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U005.1 | recover — running instances | DB has "running" instances, no process | FlowServer restarted | P0 |
| U005.2 | recover — waiting instances | DB has "waiting" instances | FlowServer restarted in waiting state | P0 |
| U005.3 | recover — completed instances | DB has "completed" instances | no recovery attempted | P0 |
| U005.4 | recover — reschedule pending jobs | waiting instance with duration | Oban job scheduled | P0 |
| U005.5 | recover — already running process | process exists for instance | skipped, no duplicate | P0 |
| U005.6 | recover — corrupt DB state | invalid context JSON | error logged, instance skipped | P1 |

#### TC-ENGINE-U006: FlowTrigger

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U006.1 | trigger — valid flow + customer | active flow, valid customer_id | `{:ok, instance_id}` | P0 |
| U006.2 | trigger — inactive flow | draft flow | `{:error, :flow_not_active}` | P0 |
| U006.3 | trigger — with initial context | `%{source: "api"}` | context includes source | P0 |
| U006.4 | trigger — duplicate prevention | same customer in same flow | `{:error, :already_in_flow}` or OK depending on config | P1 |

#### TC-ENGINE-U007: CircuitBreaker

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U007.1 | closed state — success | successful call | passes through | P0 |
| U007.2 | closed → open | N consecutive failures | state transitions to open | P0 |
| U007.3 | open state — rejects | call during open state | `{:error, :circuit_open}` | P0 |
| U007.4 | open → half-open | after timeout period | allows one test call | P0 |
| U007.5 | half-open — success → closed | test call succeeds | back to closed | P0 |
| U007.6 | half-open — failure → open | test call fails | back to open | P0 |
| U007.7 | reset — manual | explicit reset call | back to closed | P1 |

#### TC-ENGINE-U008: Duration

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U008.1 | parse "3d" | "3d" | 259_200 seconds | P0 |
| U008.2 | parse "2h" | "2h" | 7_200 seconds | P0 |
| U008.3 | parse "30m" | "30m" | 1_800 seconds | P0 |
| U008.4 | parse "45s" | "45s" | 45 seconds | P0 |
| U008.5 | parse "1d12h" | "1d12h" | 129_600 seconds | P1 |
| U008.6 | parse invalid | "abc" | `{:error, _}` | P0 |
| U008.7 | parse empty | "" | `{:error, _}` | P1 |
| U008.8 | to_datetime | "2h" from now | ~2 hours ahead | P1 |

### 3.2 Integration Tests

| ID | Test Case | Description | Priority |
|----|-----------|-------------|----------|
| I-ENGINE-001 | Trigger-to-completion full flow | trigger → entry → email → wait → event → goal → exit; verify all DB records | P0 |
| I-ENGINE-002 | Wait + Oban resume | wait node creates Oban job → job executes → flow resumes | P0 |
| I-ENGINE-003 | Event routing end-to-end | create waiting instance → dispatch event via API → flow continues | P0 |
| I-ENGINE-004 | Recovery after simulated crash | insert "running" instance in DB → call recover → verify GenServer started | P0 |
| I-ENGINE-005 | Multiple flows for same customer | customer in flow_a and flow_b → event_a routes only to flow_a | P1 |
| I-ENGINE-006 | FlowServer + persistence round-trip | execute 5 nodes → kill process → recover → verify context intact | P0 |
| I-ENGINE-007 | Circuit breaker + external call | email send fails 5 times → circuit opens → next email skipped gracefully | P1 |
| I-ENGINE-008 | Parallel group execution | parallel_group with 3 branches → all execute → results merged | P1 |
| I-ENGINE-009 | Sub-flow invocation | parent flow triggers sub-flow → sub completes → parent resumes | P1 |
| I-ENGINE-010 | Dry-run full flow | dry_run flag → email "sent" without actual delivery, results recorded | P0 |

---

## 4. დომეინი #3: Node System

**მოდულები**: 24+ node modules in `engine/nodes/`

### 4.1 Trigger Nodes — Unit Tests

#### TC-NODE-TRIGGER-U001: EventEntry

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | execute — matching event type | event_type matches config | `{:completed, event_data}` | P0 |
| U001.2 | validate — missing event_type | `%{}` | `{:error, _}` | P0 |
| U001.3 | category/0 | — | `:trigger` | P0 |

#### TC-NODE-TRIGGER-U002: SegmentEntry

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | execute — customer in segment | customer matches segment criteria | `{:completed, _}` | P0 |
| U002.2 | execute — customer not in segment | customer doesn't match | `{:failed, :not_in_segment}` | P1 |
| U002.3 | validate — missing segment_id | `%{}` | `{:error, _}` | P0 |

#### TC-NODE-TRIGGER-U003: WebhookEntry

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | execute — valid webhook payload | `%{data: ...}` | `{:completed, parsed_data}` | P0 |
| U003.2 | validate — valid config | `%{path: "/hook"}` | `:ok` | P0 |

### 4.2 Action/Channel Nodes — Unit Tests

#### TC-NODE-CHANNEL-U001: SendEmail

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | execute — template mode | `%{template_id: "t1"}` | `{:completed, %{delivery_id: ...}}` | P0 |
| U001.2 | execute — custom subject/body | `%{subject: "Hi", body: "..."}` | `{:completed, _}` | P0 |
| U001.3 | execute — context interpolation | body has `{{customer.name}}` | name replaced in output | P0 |
| U001.4 | execute — missing recipient email | context without _email | `{:failed, :no_recipient}` | P0 |
| U001.5 | execute — provider failure | mock returns error | `{:failed, reason}` | P0 |
| U001.6 | execute — dry_run mode | `_dry_run: true` | `{:completed, %{simulated: true}}` | P0 |
| U001.7 | validate — missing template and subject | `%{}` | `{:error, _}` | P1 |
| U001.8 | category/0 | — | `:action` | P0 |

#### TC-NODE-CHANNEL-U002: SendSms

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | execute — valid phone | `%{message: "Hi"}` + context._phone | `{:completed, _}` | P0 |
| U002.2 | execute — missing phone | no _phone in context | `{:failed, :no_recipient}` | P0 |
| U002.3 | execute — provider error | mock returns error | `{:failed, _}` | P0 |

#### TC-NODE-CHANNEL-U003: SendPush

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | execute — valid push | `%{title: "...", body: "..."}` | `{:completed, _}` | P0 |
| U003.2 | execute — no device token | missing push token | `{:failed, :no_device}` | P1 |

#### TC-NODE-CHANNEL-U004: SendWhatsapp

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U004.1 | execute — valid message | `%{message: "Hi"}` + phone | `{:completed, _}` | P0 |
| U004.2 | execute — template message | `%{template_name: "..."}` | `{:completed, _}` | P1 |

#### TC-NODE-CHANNEL-U005: SendInApp

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U005.1 | execute — valid in-app | `%{content: "..."}` | `{:completed, _}` | P0 |

#### TC-NODE-CHANNEL-U006: CallWebhook

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U006.1 | execute — successful POST | `%{url: "...", method: "POST"}` | `{:completed, %{status: 200}}` | P0 |
| U006.2 | execute — 4xx response | server returns 400 | `{:failed, _}` | P0 |
| U006.3 | execute — timeout | server hangs | `{:failed, :timeout}` | P0 |
| U006.4 | execute — context in payload | `%{body: "{{customer.id}}"}` | customer_id interpolated | P1 |
| U006.5 | validate — missing url | `%{}` | `{:error, _}` | P0 |

### 4.3 Action/Data Nodes — Unit Tests

#### TC-NODE-DATA-U001: UpdateProfile

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | execute — set properties | `%{properties: %{vip: true}}` | customer updated | P0 |
| U001.2 | execute — merge mode | existing + new properties | merged, not replaced | P0 |

#### TC-NODE-DATA-U002: AddTag

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | execute — add new tag | `%{tag: "engaged"}` | tag added | P0 |
| U002.2 | execute — duplicate tag | tag already exists | no duplicate, idempotent | P0 |

#### TC-NODE-DATA-U003: CustomCode

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | execute — valid expression | `%{code: "1 + 1"}` | `{:completed, 2}` | P0 |
| U003.2 | execute — access context | code referencing context vars | correct value returned | P1 |
| U003.3 | execute — runtime error | division by zero | `{:failed, _}` | P0 |
| U003.4 | execute — sandbox violation | forbidden operations | `{:failed, :sandbox_violation}` | P0 |

#### TC-NODE-DATA-U004: TrackConversion

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U004.1 | execute — record conversion | `%{goal: "purchase"}` | conversion recorded in DB | P0 |
| U004.2 | execute — with value | `%{goal: "purchase", value: 99.99}` | value stored | P1 |

#### TC-NODE-DATA-U005: MemoryRecall

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U005.1 | execute — existing memory | key exists | `{:completed, %{memory: data}}` | P0 |
| U005.2 | execute — no memory | key doesn't exist | `{:completed, %{memory: nil}}` | P0 |

### 4.4 Action/AI Nodes — Unit Tests

#### TC-NODE-AI-U001: Think

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | execute — successful reasoning | valid prompt + context | `{:completed, %{reasoning: "..."}}` | P0 |
| U001.2 | execute — AI provider error | mock returns error | `{:failed, _}` | P0 |
| U001.3 | execute — dry_run | _dry_run: true | simulated result | P1 |

#### TC-NODE-AI-U002: Decide

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | execute — returns branch key | AI picks "option_a" | `{:branched, "option_a", _}` | P0 |
| U002.2 | execute — invalid branch from AI | AI returns unknown branch | fallback or error | P0 |

#### TC-NODE-AI-U003: Notify

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | execute — AI crafts notification | context + template | `{:completed, %{message: "..."}}` | P0 |

#### TC-NODE-AI-U004: Agent

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U004.1 | execute — agent loop completes | config with max_steps | `{:completed, _}` after N steps | P0 |
| U004.2 | execute — agent uses tools | tool calls in loop | tools executed, results accumulated | P0 |
| U004.3 | execute — max steps exceeded | max_steps: 3, needs 5 | stops at 3 with partial result | P1 |

#### TC-NODE-AI-U005: FlowRouter

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U005.1 | execute — routes to correct flow | AI selects target flow | `{:completed, %{target_flow_id: "..."}}` | P0 |
| U005.2 | execute — no matching flow | AI can't decide | `{:failed, _}` | P1 |

### 4.5 Condition Nodes — Unit Tests

#### TC-NODE-COND-U001: Condition

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | equals — match | `%{field: "status", operator: "equals", value: "active"}` | `{:branched, "true", _}` | P0 |
| U001.2 | equals — no match | value doesn't match | `{:branched, "false", _}` | P0 |
| U001.3 | not_equals | field != value | correct branch | P0 |
| U001.4 | greater_than | numeric comparison | correct branch | P0 |
| U001.5 | less_than | numeric comparison | correct branch | P0 |
| U001.6 | contains — string | substring match | correct branch | P0 |
| U001.7 | not_contains | substring no match | correct branch | P0 |
| U001.8 | exists — field present | field in context | "true" branch | P0 |
| U001.9 | not_exists — field missing | field not in context | "true" branch | P0 |
| U001.10 | in — list membership | value in list | correct branch | P0 |
| U001.11 | matches — regex | pattern matches | correct branch | P1 |
| U001.12 | nested field access | `"customer.properties.vip"` | resolves correctly | P1 |
| U001.13 | nil field value | field is nil | handled gracefully | P0 |

#### TC-NODE-COND-U002: ABSplit

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | execute — deterministic per customer | same customer_id twice | same variant both times | P0 |
| U002.2 | execute — distribution matches weights | 10K customers, 70/30 split | ~70%/30% ±5% | P0 |
| U002.3 | validate — < 2 variants | 1 variant | `{:error, _}` | P0 |
| U002.4 | validate — weights don't sum to 100 | sum = 90 | `{:error, _}` | P1 |
| U002.5 | validate — empty variants | `[]` | `{:error, _}` | P0 |

#### TC-NODE-COND-U003: FrequencyCap

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | execute — under cap | 2 sends, cap = 5 | `{:branched, "allowed", _}` | P0 |
| U003.2 | execute — at cap | 5 sends, cap = 5 | `{:branched, "capped", _}` | P0 |
| U003.3 | execute — window expired | old sends outside window | `{:branched, "allowed", _}` | P0 |
| U003.4 | execute — per-channel cap | email cap vs sms cap | independent counts | P1 |
| U003.5 | validate — missing max | no max in config | `{:error, _}` | P0 |

#### TC-NODE-COND-U004: CheckSegment

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U004.1 | execute — in segment | customer matches criteria | `{:branched, "in_segment", _}` | P0 |
| U004.2 | execute — not in segment | customer doesn't match | `{:branched, "not_in_segment", _}` | P0 |

#### TC-NODE-COND-U005: PreferenceGate

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U005.1 | execute — opted in | customer preference == true | `{:branched, "opted_in", _}` | P0 |
| U005.2 | execute — opted out | preference == false | `{:branched, "opted_out", _}` | P0 |
| U005.3 | execute — no preference set | preference is nil | default behavior | P1 |

### 4.6 Wait Nodes — Unit Tests

#### TC-NODE-WAIT-U001: Wait (Duration)

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | execute — returns waiting config | `%{duration: "2h"}` | `{:waiting, %{duration: "2h"}}` | P0 |
| U001.2 | resume — timer expired | resume signal | `{:completed, _}` | P0 |
| U001.3 | validate — invalid duration | `%{duration: "abc"}` | `{:error, _}` | P0 |

#### TC-NODE-WAIT-U002: WaitUntil

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | execute — future datetime | datetime 2 hours ahead | `{:waiting, %{until: datetime}}` | P0 |
| U002.2 | execute — past datetime | datetime in the past | `{:completed, _}` immediately | P1 |
| U002.3 | validate — invalid datetime | "not-a-date" | `{:error, _}` | P0 |

#### TC-NODE-WAIT-U003: WaitForEvent

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | execute — registers wait | `%{event_type: "purchase"}` | `{:waiting, %{event_type: "purchase"}}` | P0 |
| U003.2 | resume — event received | matching event | `{:completed, event_data}` | P0 |
| U003.3 | resume — timeout (no event) | timeout fires | `{:completed, %{timed_out: true}}` or branch | P0 |
| U003.4 | resume — wrong event type | non-matching event | stays waiting | P1 |
| U003.5 | validate — missing event_type | `%{}` | `{:error, _}` | P0 |

### 4.7 End Nodes — Unit Tests

#### TC-NODE-END-U001: Exit

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | execute | any context | `{:completed, %{exit_reason: "normal"}}` | P0 |
| U001.2 | category/0 | — | `:end` | P0 |

#### TC-NODE-END-U002: GoalReached

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | execute — records goal | `%{goal: "purchase"}` | conversion recorded + `{:completed, _}` | P0 |
| U002.2 | execute — goal with metadata | `%{goal: "purchase", value: 50}` | metadata stored | P1 |

### 4.8 Orchestration Nodes — Unit Tests

#### TC-NODE-ORCH-U001: ParallelGroup

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | execute — all branches succeed | 3 parallel tasks | `{:completed, [r1, r2, r3]}` | P0 |
| U001.2 | execute — one branch fails | 1 of 3 fails | partial results or failure policy | P0 |
| U001.3 | execute — timeout | one branch slow | timeout behavior defined | P1 |
| U001.4 | validate — empty branches | `%{branches: []}` | `{:error, _}` | P1 |

#### TC-NODE-ORCH-U002: SubFlow

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | execute — valid sub-flow | existing flow_id | `{:completed, sub_result}` | P0 |
| U002.2 | execute — nonexistent sub-flow | invalid flow_id | `{:failed, :flow_not_found}` | P0 |
| U002.3 | execute — context forwarding | parent context vars | available in sub-flow | P1 |

---

## 5. დომეინი #4: Persistence Layer

**მოდულები**: `InstanceStore`, `StepStore`

### 5.1 Unit Tests

#### TC-PERSIST-U001: InstanceStore

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | create_instance | valid attrs | `{:ok, %FlowInstance{}}` | P0 |
| U001.2 | get_instance | valid id | `%FlowInstance{}` with preloads | P0 |
| U001.3 | update_status — valid transition | running → waiting | `{:ok, updated}` | P0 |
| U001.4 | update_status — invalid transition | completed → running | `{:error, _}` | P0 |
| U001.5 | update_context | new context map | merged into instance | P0 |
| U001.6 | update_current_nodes | `["node_3"]` | current_nodes updated | P0 |
| U001.7 | list_for_recovery | — | running + waiting instances | P0 |
| U001.8 | list_by_flow | flow_id | all instances for flow | P0 |
| U001.9 | count_by_status | flow_id | `%{running: 5, waiting: 3, ...}` | P1 |

#### TC-PERSIST-U002: StepStore

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | record_step — started | step attrs | `{:ok, %ExecutionStep{status: "started"}}` | P0 |
| U002.2 | complete_step | step + output | status="completed", output saved | P0 |
| U002.3 | fail_step | step + error | status="failed", error saved | P0 |
| U002.4 | list_by_instance | instance_id | ordered steps | P0 |
| U002.5 | frequency_cap_query | customer_id, channel, window | count in window | P0 |
| U002.6 | step_duration | completed step | duration_ms calculated | P1 |

---

## 6. დომეინი #5: Marketing Context

**მოდული**: `Kalcifer.Marketing`
**სქემა**: `Journey`

### 6.1 Unit Tests

#### TC-MKT-U001: Journey CRUD

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | create_journey — valid | `%{name: "Welcome", flow_id: id}` | `{:ok, %Journey{status: "draft"}}` | P0 |
| U001.2 | create_journey — without flow_id | `%{name: "Test"}` | `{:error, _}` | P0 |
| U001.3 | get_journey | valid id | `%Journey{}` | P0 |
| U001.4 | list_journeys — tenant isolation | tenant_a | only tenant_a journeys | P0 |
| U001.5 | list_journeys — status filter | `status: "active"` | only active | P1 |
| U001.6 | list_journeys — tag filter | `tag: "onboarding"` | matching tags | P1 |
| U001.7 | update_journey — draft | `%{name: "New"}` | `{:ok, updated}` | P0 |
| U001.8 | delete_journey — draft | draft journey | `{:ok, deleted}` | P0 |
| U001.9 | delete_journey — active | active journey | `{:error, _}` | P0 |

#### TC-MKT-U002: Journey Lifecycle

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | launch_journey (draft → active) | draft journey + published version | `{:ok, journey}` + underlying flow activated | P0 |
| U002.2 | launch_journey — no flow version | journey without published version | `{:error, _}` | P0 |
| U002.3 | pause_journey | active journey | `{:ok, paused}` + flow paused | P0 |
| U002.4 | resume_journey | paused journey | `{:ok, active}` + flow resumed | P0 |
| U002.5 | archive_journey | active/paused journey | `{:ok, archived}` + flow archived | P0 |
| U002.6 | journey status mirrors flow | launch_journey | journey.status == flow.status | P0 |

#### TC-MKT-U003: Journey Schema Changesets

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | create_changeset — goal_config validation | valid goal JSON | valid changeset | P1 |
| U003.2 | create_changeset — audience_criteria | valid criteria | valid changeset | P1 |
| U003.3 | status_changeset — valid transition | "draft" → "active" | valid changeset | P0 |
| U003.4 | status_changeset — invalid transition | "archived" → "active" | invalid changeset | P0 |

### 6.2 Integration Tests

| ID | Test Case | Description | Priority |
|----|-----------|-------------|----------|
| I-MKT-001 | Journey → Flow cascade | launch journey → verify flow + version activated | P0 |
| I-MKT-002 | Journey pause cascades | pause journey → all running instances pause | P1 |
| I-MKT-003 | Journey archive cleanup | archive journey → verify instances handled | P1 |

---

## 7. დომეინი #6: Customers Context

**მოდული**: `Kalcifer.Customers`
**სქემა**: `Customer`

### 7.1 Unit Tests

#### TC-CUST-U001: Customer CRUD

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | create_customer — valid | `%{external_id: "ext_1", email: "a@b.com"}` | `{:ok, %Customer{}}` | P0 |
| U001.2 | create_customer — duplicate external_id | same tenant + external_id | `{:error, _}` unique constraint | P0 |
| U001.3 | get_customer | valid id | `%Customer{}` | P0 |
| U001.4 | get_customer_by_external_id | tenant_id + external_id | `%Customer{}` | P0 |
| U001.5 | list_customers — pagination | `page: 2, per_page: 10` | correct page | P1 |
| U001.6 | update_customer — properties | `%{properties: %{plan: "pro"}}` | properties updated | P0 |
| U001.7 | upsert_customer — new | non-existing external_id | created | P0 |
| U001.8 | upsert_customer — existing | existing external_id | updated | P0 |

#### TC-CUST-U002: Tags & Preferences

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | add_tag — new tag | `"vip"` | tags includes "vip" | P0 |
| U002.2 | add_tag — duplicate | tag already exists | no duplicate | P0 |
| U002.3 | remove_tag | `"vip"` | tags excludes "vip" | P0 |
| U002.4 | remove_tag — nonexistent | tag not present | no error | P1 |
| U002.5 | update_preferences | `%{email: true, sms: false}` | preferences updated | P0 |
| U002.6 | field_coverage | `["email", "phone"]` | `%{email: 80.0, phone: 45.0}` percentage | P1 |

#### TC-CUST-U003: Segment Evaluator

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | member? — property match | `%{field: "plan", operator: "equals", value: "pro"}` | true | P0 |
| U003.2 | member? — tag-based | `%{has_tag: "vip"}` | true if tagged | P0 |
| U003.3 | member? — compound criteria (AND) | multiple conditions | all must match | P1 |
| U003.4 | member? — compound criteria (OR) | multiple conditions | any must match | P1 |
| U003.5 | member? — nested property | `"properties.subscription.tier"` | deep access | P1 |

---

## 8. დომეინი #7: Channels Context

**მოდული**: `Kalcifer.Channels`
**სქემა**: `Delivery`

### 8.1 Unit Tests

#### TC-CHAN-U001: Delivery CRUD

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | create_delivery | valid attrs | `{:ok, %Delivery{status: "pending"}}` | P0 |
| U001.2 | update_status — sent | `"sent"` | status updated + timestamps | P0 |
| U001.3 | update_status — failed | `"failed"` + error | status + error stored | P0 |
| U001.4 | update_status — bounced | `"bounced"` | status updated | P0 |
| U001.5 | list_by_instance | instance_id | all deliveries for instance | P0 |
| U001.6 | list_by_tenant | tenant_id + filters | filtered results | P1 |

#### TC-CHAN-U002: ChannelSender

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | send — email via provider | email config | provider called, delivery created | P0 |
| U002.2 | send — sms via provider | sms config | provider called | P0 |
| U002.3 | send — provider not configured | missing provider | `{:error, :no_provider}` | P0 |

#### TC-CHAN-U003: ProviderRegistry

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | register provider | email → SendGrid module | registered in ETS | P0 |
| U003.2 | lookup provider | :email | correct module | P0 |
| U003.3 | lookup unregistered | :telegram | `nil` | P0 |

#### TC-CHAN-U004: SendMessageJob (Oban)

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U004.1 | perform — successful send | valid job args | delivery status = sent | P0 |
| U004.2 | perform — provider failure | mock error | delivery status = failed | P0 |
| U004.3 | perform — retry on transient error | 503 error | job re-enqueued | P1 |

### 8.2 Integration Tests

| ID | Test Case | Description | Priority |
|----|-----------|-------------|----------|
| I-CHAN-001 | Email send end-to-end | node execute → Oban job → provider mock → delivery record updated | P0 |
| I-CHAN-002 | Webhook status callback | SendGrid webhook → delivery status update | P0 |
| I-CHAN-003 | Multi-channel flow | flow sends email + SMS + push in sequence | P1 |

---

## 9. დომეინი #8: Analytics Context

**მოდული**: `Kalcifer.Analytics`
**სქემები**: `FlowStats`, `NodeStats`, `Conversion`

### 9.1 Unit Tests

#### TC-ANLX-U001: Stats CRUD

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | upsert_flow_stats — new | flow_id, date, counts | record created | P0 |
| U001.2 | upsert_flow_stats — existing | same flow_id + date | counts incremented | P0 |
| U001.3 | upsert_node_stats — new | node_id, date, counts | record created | P0 |
| U001.4 | upsert_node_stats — with branch | branch key | branch_counts updated | P1 |
| U001.5 | flow_summary — date range | flow_id + start..end | aggregated counts | P0 |
| U001.6 | flow_summary — no data | new flow | zeroed counts | P1 |
| U001.7 | node_breakdown | flow_id, version | per-node stats | P0 |
| U001.8 | node_avg_durations | flow_id | `%{node_id => ms}` | P1 |

#### TC-ANLX-U002: Conversions

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | record_conversion | goal, customer, flow, value | `{:ok, %Conversion{}}` | P0 |
| U002.2 | conversion_count — date range | flow_id + range | correct count | P0 |
| U002.3 | conversion_count — empty | no conversions | 0 | P1 |

#### TC-ANLX-U003: Funnel & A/B

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | funnel — ordered nodes | `[node_1, node_2, node_3]` | descending counts | P0 |
| U003.2 | funnel — empty flow | no instances | all zeros | P1 |
| U003.3 | ab_test_results | ab_split node_id | `%{"A" => n, "B" => m}` | P0 |

#### TC-ANLX-U004: Collector

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U004.1 | handle instance entered event | `:instance_entered` broadcast | flow_stats.entered += 1 | P0 |
| U004.2 | handle instance completed event | `:instance_completed` | flow_stats.completed += 1 | P0 |
| U004.3 | handle node executed event | `:node_executed` | node_stats updated | P0 |
| U004.4 | handle batch events | 100 events rapid fire | all counted correctly | P1 |

### 9.2 Integration Tests

| ID | Test Case | Description | Priority |
|----|-----------|-------------|----------|
| I-ANLX-001 | Full pipeline flow | trigger flow → complete → verify stats in DB | P0 |
| I-ANLX-002 | A/B stats tracking | 100 customers through A/B split → verify distribution in stats | P1 |
| I-ANLX-003 | Funnel accuracy | flow with 5 nodes, 50% dropout per step → funnel matches | P1 |

---

## 10. დომეინი #9: Tenants & Auth

**მოდული**: `Kalcifer.Tenants`
**სქემა**: `Tenant`

### 10.1 Unit Tests

#### TC-TENANT-U001: Tenant Management

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | create_tenant | `%{name: "Acme"}` | `{:ok, tenant}` with api_key | P0 |
| U001.2 | get_tenant | valid id | `%Tenant{}` | P0 |
| U001.3 | get_tenant_by_api_key_hash | SHA256 hash | correct tenant | P0 |
| U001.4 | get_tenant_by_api_key_hash — wrong hash | random hash | `nil` | P0 |
| U001.5 | regenerate_api_key | existing tenant | new key, old invalidated | P0 |
| U001.6 | hash_api_key | `"kal_abc123"` | SHA256 hex string | P0 |
| U001.7 | generate_api_key | — | starts with `"kal_"` | P0 |

#### TC-TENANT-U002: Settings & AI Config

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | update_settings | `%{timezone: "UTC"}` | merged into settings JSONB | P0 |
| U002.2 | update_settings — preserves existing | add new key | old keys preserved | P0 |
| U002.3 | get_setting — exists | `"timezone"` | value from settings | P0 |
| U002.4 | get_setting — default | missing key, default: "UTC" | "UTC" | P0 |
| U002.5 | ai_config | tenant with AI keys | `%{model: ..., provider: ..., api_key: ...}` | P0 |
| U002.6 | ai_config — no keys | tenant without AI config | defaults or empty | P0 |
| U002.7 | provider_keys | tenant with multiple providers | `%{anthropic: true, openai: false}` | P1 |

#### TC-TENANT-U003: API Key Auth Plug

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | valid Bearer token | `Authorization: Bearer kal_...` | conn.assigns.tenant set | P0 |
| U003.2 | missing header | no Authorization | 401 Unauthorized | P0 |
| U003.3 | invalid token | `Bearer invalid_key` | 401 Unauthorized | P0 |
| U003.4 | malformed header | `Basic kal_...` | 401 Unauthorized | P0 |
| U003.5 | expired/revoked key | old key after regeneration | 401 Unauthorized | P0 |

#### TC-TENANT-U004: Rate Limiter Plug

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U004.1 | under limit | normal request rate | passes through | P0 |
| U004.2 | at limit | burst of requests | 429 Too Many Requests | P0 |
| U004.3 | window reset | wait for window reset | allows again | P1 |
| U004.4 | per-tenant isolation | tenant_a at limit | tenant_b unaffected | P0 |

---

## 11. დომეინი #10: API Layer

**მოდულები**: Controllers, Router, Plugs, WebSocket

### 11.1 Controller Unit Tests

#### TC-API-U001: FlowController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U001.1 | POST /api/v1/flows — create | valid body | 201 + flow JSON | P0 |
| U001.2 | POST /api/v1/flows — invalid | empty body | 422 + errors | P0 |
| U001.3 | GET /api/v1/flows — list | auth header | 200 + [flows] | P0 |
| U001.4 | GET /api/v1/flows/:id — show | valid id | 200 + flow | P0 |
| U001.5 | GET /api/v1/flows/:id — not found | invalid id | 404 | P0 |
| U001.6 | PUT /api/v1/flows/:id — update | valid body | 200 + updated | P0 |
| U001.7 | DELETE /api/v1/flows/:id | draft flow | 204 | P0 |
| U001.8 | POST /api/v1/flows/:id/activate | draft + version | 200 + active flow | P0 |
| U001.9 | POST /api/v1/flows/:id/pause | active flow | 200 + paused flow | P0 |
| U001.10 | POST /api/v1/flows/:id/archive | any valid state | 200 + archived | P0 |
| U001.11 | POST /api/v1/flows/:id/preflight | flow with graph | 200 + preflight results | P1 |
| U001.12 | POST /api/v1/flows/import | valid export JSON | 201 + imported flow | P1 |
| U001.13 | GET /api/v1/flows/:id/export | valid flow | 200 + export JSON | P1 |
| U001.14 | No auth header | any endpoint | 401 | P0 |
| U001.15 | Wrong tenant's flow | other tenant's flow_id | 404 | P0 |

#### TC-API-U002: FlowVersionController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U002.1 | GET /api/v1/flows/:id/versions | valid flow | 200 + [versions] | P0 |
| U002.2 | GET /api/v1/flows/:id/versions/:num | valid pair | 200 + version | P0 |
| U002.3 | POST /api/v1/flows/:id/versions | valid graph | 201 + version | P0 |

#### TC-API-U003: InstanceController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U003.1 | GET /api/v1/flows/:id/instances | valid flow | 200 + [instances] | P0 |
| U003.2 | GET /api/v1/instances/:id | valid id | 200 + instance + steps | P0 |
| U003.3 | POST /api/v1/instances/:id/cancel | running instance | 200 + cancelled | P0 |
| U003.4 | Cancel completed instance | completed | 422 error | P1 |

#### TC-API-U004: TriggerController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U004.1 | POST /api/v1/flows/:id/trigger | active flow + customer_id | 201 + instance_id | P0 |
| U004.2 | Trigger inactive flow | draft flow | 422 | P0 |
| U004.3 | Trigger with context | `%{context: %{source: "api"}}` | context passed to instance | P0 |

#### TC-API-U005: EventController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U005.1 | POST /api/v1/events | valid event | 200 | P0 |
| U005.2 | Event with missing fields | no customer_id | 422 | P0 |
| U005.3 | Event for non-waiting customer | valid but no match | 200 (silently ignored) | P0 |

#### TC-API-U006: CustomerController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U006.1 | POST /api/v1/customers | valid body | 201 + customer | P0 |
| U006.2 | GET /api/v1/customers | auth header | 200 + [customers] | P0 |
| U006.3 | GET /api/v1/customers/:id | valid id | 200 + customer | P0 |
| U006.4 | PUT /api/v1/customers/:id | update body | 200 + updated | P0 |
| U006.5 | POST /api/v1/customers/:id/tags | `%{tag: "vip"}` | 200 + updated | P0 |
| U006.6 | PUT /api/v1/customers/:id/preferences | prefs body | 200 + updated | P0 |

#### TC-API-U007: JourneyController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U007.1 | POST /api/v1/journeys | valid body | 201 + journey | P0 |
| U007.2 | GET /api/v1/journeys | auth header | 200 + [journeys] | P0 |
| U007.3 | POST /api/v1/journeys/:id/launch | draft journey | 200 + active | P0 |
| U007.4 | POST /api/v1/journeys/:id/pause | active journey | 200 + paused | P0 |

#### TC-API-U008: AnalyticsController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U008.1 | GET /api/v1/flows/:id/analytics/summary | valid flow | 200 + summary | P0 |
| U008.2 | GET /api/v1/flows/:id/analytics/nodes | valid flow | 200 + node breakdown | P0 |
| U008.3 | GET /api/v1/flows/:id/analytics/funnel | node_ids param | 200 + funnel data | P1 |
| U008.4 | GET /api/v1/flows/:id/analytics/ab/:node_id | ab_split node | 200 + A/B results | P1 |

#### TC-API-U009: WebhookController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U009.1 | POST /api/v1/webhooks/sendgrid | valid SendGrid event | 200 | P0 |
| U009.2 | POST /api/v1/webhooks/twilio | valid Twilio status | 200 | P0 |
| U009.3 | Invalid webhook payload | malformed JSON | 400 | P0 |

#### TC-API-U010: HealthController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U010.1 | GET /api/v1/health | — | 200 + status: ok | P0 |
| U010.2 | GET /api/v1/health/metrics | — | 200 + metrics JSON | P1 |

#### TC-API-U011: SettingsController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U011.1 | GET /api/v1/settings | auth | 200 + current settings | P0 |
| U011.2 | PUT /api/v1/settings | new settings body | 200 + updated | P0 |
| U011.3 | POST /api/v1/settings/api-key/regenerate | auth | 200 + new key (shown once) | P0 |

#### TC-API-U012: DeliveryController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U012.1 | GET /api/v1/deliveries — list by tenant | auth header | 200 + [deliveries] | P0 |
| U012.2 | GET /api/v1/deliveries/:id | valid id | 200 + delivery detail | P0 |
| U012.3 | GET /api/v1/deliveries/stats | auth | 200 + aggregate stats | P1 |
| U012.4 | Filter by status | `status=failed` | only failed deliveries | P1 |
| U012.5 | Filter by channel | `channel=email` | only email deliveries | P1 |

#### TC-API-U013: AuditController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U013.1 | GET /api/v1/audit | auth | 200 + [audit_entries] | P0 |
| U013.2 | Filter by action | `action=flow_created` | filtered entries | P1 |
| U013.3 | Filter by date range | start + end params | filtered entries | P1 |
| U013.4 | Filter by resource | `resource_type=flow&resource_id=x` | resource audit trail | P1 |

#### TC-API-U014: MigrationController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U012.1 | POST /api/v1/flows/:id/migrate | target version + strategy | 200 + migration result | P0 |
| U012.2 | POST /api/v1/flows/:id/rollback | target version | 200 + rollback result | P0 |

#### TC-API-U013: SimulationController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U013.1 | POST /api/v1/flows/:id/simulate | simulation params | 200 + dry run results | P0 |

#### TC-API-U014: ChatController & ConversationController

| ID | Test Case | Endpoint | Expected | Priority |
|----|-----------|----------|----------|----------|
| U014.1 | POST /api/v1/chat/completions | valid message | 200 + AI response | P0 |
| U014.2 | GET /api/v1/conversations | auth | 200 + [conversations] | P0 |
| U014.3 | POST /api/v1/conversations | create conv | 201 | P0 |
| U014.4 | GET /api/v1/conversations/:id | valid id | 200 + messages | P0 |

### 11.2 WebSocket Tests

| ID | Test Case | Description | Priority |
|----|-----------|-------------|----------|
| WS-001 | Join flow channel | valid flow_id + auth | joined successfully | P0 |
| WS-002 | Join unauthorized | wrong tenant | error: unauthorized | P0 |
| WS-003 | Receive node execution event | flow executes node | broadcast received | P0 |
| WS-004 | Receive instance status change | instance completes | broadcast received | P0 |
| WS-005 | Multiple subscribers | 3 clients on same flow | all receive events | P1 |

---

## 12. დომეინი #11: Versioning

**მოდულები**: `Migrator`, `NodeMapper`

### 12.1 Unit Tests

#### TC-VER-U001: NodeMapper

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | build_mapping — identical graphs | same nodes | `%{id => id}` 1:1 mapping | P0 |
| U001.2 | build_mapping — renamed node | same type, different id | maps old → new | P0 |
| U001.3 | build_mapping — added node | new node in v2 | new node not in mapping | P0 |
| U001.4 | build_mapping — removed node | node missing in v2 | old node unmapped | P0 |
| U001.5 | check_migration_safety — safe | all nodes mapped | `:safe` | P0 |
| U001.6 | check_migration_safety — warning | some nodes removed | `{:warning, removed_nodes}` | P0 |
| U001.7 | detect_wait_changes — config changed | wait duration 2h → 4h | `[{node_id, :config_changed}]` | P0 |
| U001.8 | detect_wait_changes — no changes | identical wait configs | `[]` | P0 |

#### TC-VER-U002: Migrator

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | migrate — migrate_all | 5 running instances | all migrated to new version | P0 |
| U002.2 | migrate — new_entries_only | 5 running instances | instances stay, flag updated | P0 |
| U002.3 | migrate — waiting instance | instance at wait node | wait re-registered on new version | P0 |
| U002.4 | migrate — instance at removed node | node removed in v2 | handled per policy | P0 |
| U002.5 | rollback | 5 migrated instances | rolled back to previous version | P0 |
| U002.6 | rollback — to non-adjacent version | v3 → v1 | `{:error, _}` or multi-step | P1 |

### 12.2 Property Tests

| ID | Property | Description | Priority |
|----|----------|-------------|----------|
| P-VER-001 | Mapping completeness | build_mapping always covers all old nodes or marks them explicitly | P0 |
| P-VER-002 | Mapping determinism | same input → same mapping | P0 |
| P-VER-003 | Round-trip safety | migrate v1→v2 then rollback = consistent state | P0 |
| P-VER-004 | Wait change detection | if wait config differs, always detected | P0 |

---

## 13. დომეინი #12: AI Subsystem

**მოდულები**: `AI.Client`, `AI.Tools`, `AI.Context`, `AI.AgentFlows`, Council Routing

### 13.1 Unit Tests

#### TC-AI-U001: Client

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | chat — successful response | valid messages | `{:ok, response}` | P0 |
| U001.2 | chat — provider error | mock returns error | `{:error, _}` | P0 |
| U001.3 | chat — with tools | messages + tool definitions | response may include tool_calls | P0 |
| U001.4 | chat — streaming | stream: true | stream of chunks | P1 |

#### TC-AI-U002: Tools

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U002.1 | definitions — returns all tools | — | list of tool schemas | P0 |
| U002.2 | execute — list_flows | `%{name: "list_flows"}` | flows listed | P0 |
| U002.3 | execute — create_flow | valid args | flow created | P0 |
| U002.4 | execute — get_flow_graph | flow_id | graph returned | P0 |
| U002.5 | execute — add_node | node config | node added to graph | P0 |
| U002.6 | execute — modify_node | node_id + changes | node updated | P0 |
| U002.7 | execute — remove_node | node_id | node removed | P0 |
| U002.8 | execute — analyze_flow | flow_id | analysis returned | P0 |
| U002.9 | execute — debug_instance | instance_id | debug info | P0 |
| U002.10 | execute — list_node_types | — | all registered types | P0 |
| U002.11 | execute — classify_session | messages | session classification | P1 |
| U002.12 | execute — remember/recall | key-value | memory stored/retrieved | P0 |
| U002.13 | execute — unknown tool | `"nonexistent"` | `{:error, :unknown_tool}` | P0 |

#### TC-AI-U003: Context & Memory

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U003.1 | create_conversation | tenant_id, attrs | `{:ok, conversation}` | P0 |
| U003.2 | add_message | conversation_id, role, content | message stored | P0 |
| U003.3 | get_api_messages | conversation_id | formatted for API | P0 |
| U003.4 | remember | tenant_id, key, value | memory stored | P0 |
| U003.5 | recall | tenant_id, key | `{:ok, value}` | P0 |
| U003.6 | recall — nonexistent | unknown key | `{:ok, nil}` | P0 |
| U003.7 | forget | tenant_id, key | memory deleted | P0 |
| U003.8 | recall_all | tenant_id | all memories | P0 |
| U003.9 | list_conversations — pagination | page + per_page | paginated list | P1 |
| U003.10 | archive_conversation | conversation_id | archived | P0 |
| U003.11 | delete_conversation | conversation_id | deleted | P0 |

#### TC-AI-U004: Council Routing

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U004.1 | detect council keyword | "create a council for..." | council flow triggered | P0 |
| U004.2 | no council keyword | regular message | normal chat | P0 |
| U004.3 | agent flow classification | agent-type message | correct routing | P1 |

---

## 14. დომეინი #13: Audit & Accounts

**მოდულები**: `Kalcifer.Audit`, `Kalcifer.Accounts`

### 14.1 Unit Tests

#### TC-AUDIT-U001: Audit Logging

| ID | Test Case | Input | Expected Result | Priority |
|----|-----------|-------|-----------------|----------|
| U001.1 | log — flow created | `:flow_created`, flow_id | audit entry created | P0 |
| U001.2 | log — with metadata | action + metadata map | metadata stored | P0 |
| U001.3 | list — by tenant | tenant_id | tenant's audit entries | P0 |
| U001.4 | list — date filter | start_date, end_date | filtered entries | P1 |
| U001.5 | for_resource | resource_type, resource_id | resource's audit trail | P0 |

---

## 15. Integration Tests — Cross-Domain

| ID | Test Case | Domains Involved | Description | Priority |
|----|-----------|-----------------|-------------|----------|
| I-CROSS-001 | Full journey launch → customer trigger → completion | Marketing + Flows + Engine + Channels + Analytics | Launch journey → trigger customer → email sent → event received → goal → stats recorded | P0 |
| I-CROSS-002 | Multi-tenant isolation | Tenants + Flows + Customers | tenant_a creates flow, tenant_b cannot see/trigger it | P0 |
| I-CROSS-003 | Flow with A/B split → analytics | Engine + Nodes + Analytics | 1000 customers → A/B split → verify stats distribution | P1 |
| I-CROSS-004 | Frequency cap across flows | Engine + Nodes + Channels | customer in 2 flows, email cap = 3/day → enforced globally | P1 |
| I-CROSS-005 | Version migration mid-flight | Flows + Versioning + Engine | active flow, 50 instances → migrate → verify continuity | P0 |
| I-CROSS-006 | Customer upsert + flow trigger | Customers + Engine | new event → customer upserted → flow triggered | P1 |
| I-CROSS-007 | Webhook delivery status update | Channels + API | SendGrid webhook → delivery record updated → analytics counted | P1 |
| I-CROSS-008 | AI chat → flow creation → activation | AI + Flows + Engine | chat creates flow via tools → publishes → activates | P1 |
| I-CROSS-009 | Dry-run simulation → report | Engine + Analytics + API | simulate flow → no real sends → report generated | P0 |
| I-CROSS-010 | Recovery after restart | Engine + Persistence + Versioning | kill app → restart → all instances recover at correct version | P0 |

---

## 16. E2E Tests

E2E ტესტები აერთიანებს მთლიან სისტემას — HTTP API-დან დაწყებული, DB-ის ჩათვლით.

### 16.1 E2E Flow Lifecycle

| ID | Test Case | Steps | Expected | Priority |
|----|-----------|-------|----------|----------|
| E2E-001 | Complete flow lifecycle via API | 1. POST /flows (create) → 2. POST /flows/:id/versions (graph) → 3. POST /flows/:id/activate → 4. POST /flows/:id/trigger → 5. GET /instances/:id (running) → 6. POST /events (trigger event) → 7. GET /instances/:id (completed) → 8. GET /analytics/summary | All steps succeed, analytics reflects execution | P0 |
| E2E-002 | Journey lifecycle via API | 1. POST /flows + version → 2. POST /journeys (link flow) → 3. POST /journeys/:id/launch → 4. POST /flows/:fid/trigger → 5. Verify execution → 6. POST /journeys/:id/pause → 7. POST /journeys/:id/archive | Journey and flow states sync | P0 |
| E2E-003 | Customer management + flow participation | 1. POST /customers → 2. POST /customers/:id/tags → 3. PUT /customers/:id/preferences → 4. POST /trigger (customer in flow) → 5. Verify preference_gate respected | Customer data used correctly in flow | P0 |

### 16.2 E2E Complex Flows

| ID | Test Case | Flow Structure | Expected | Priority |
|----|-----------|---------------|----------|----------|
| E2E-010 | Branching flow | entry → condition → (true: email → exit) / (false: sms → exit) | Correct branch taken based on context | P0 |
| E2E-011 | Wait + event flow | entry → email → wait_for_event(purchase, timeout:5m) → (event: goal) / (timeout: reminder_email → exit) | Event received: goal path; No event: timeout path | P0 |
| E2E-012 | A/B split flow | entry → ab_split(A:50,B:50) → (A: email_a → exit) / (B: email_b → exit) | Deterministic split, stats tracked | P0 |
| E2E-013 | Frequency cap flow | entry → freq_cap(email, 2/day) → (allowed: send_email) / (capped: skip → exit) | Capped after 2 emails | P0 |
| E2E-014 | Multi-step nurture | entry → email_1 → wait(1d) → email_2 → wait(2d) → email_3 → exit | All 3 emails sent with delays | P1 |
| E2E-015 | Parallel execution | entry → parallel(email + sms + push) → merge → exit | All channels sent concurrently | P1 |
| E2E-016 | Sub-flow invocation | entry → sub_flow(onboarding) → continue → exit | Sub-flow completes, parent resumes | P1 |
| E2E-017 | Segment-based entry | segment_entry(VIP) → send_email → exit | Only VIP customers enter | P1 |
| E2E-018 | Preference gate | entry → email → pref_gate(email_opt_in) → (in: continue) / (out: skip) → exit | Opted-out customers skip | P1 |
| E2E-019 | Custom code node | entry → custom_code(calculate discount) → email(with discount) → exit | Computed value in email | P2 |
| E2E-020 | Webhook trigger + callback | webhook_entry → process → call_webhook(external) → exit | External webhook called with data | P1 |

### 16.3 E2E Error & Edge Cases

| ID | Test Case | Scenario | Expected | Priority |
|----|-----------|----------|----------|----------|
| E2E-030 | API auth failure | All endpoints without Bearer token | 401 on all | P0 |
| E2E-031 | Cross-tenant access attempt | Tenant A's token, Tenant B's flow_id | 404 (not 403) | P0 |
| E2E-032 | Invalid graph upload | POST version with cyclic graph | 422 + validation errors | P0 |
| E2E-033 | Trigger inactive flow | POST trigger on draft flow | 422 | P0 |
| E2E-034 | Double trigger same customer | 2x POST trigger same customer+flow | Handled per config (reject or allow) | P0 |
| E2E-035 | Cancel running instance via API | POST /instances/:id/cancel | Instance stops, no more nodes execute | P0 |
| E2E-036 | Rate limiting | Burst 200 requests in 1s | 429 returned after limit | P1 |
| E2E-037 | Large graph (100+ nodes) | Upload and execute | No timeout, correct execution | P1 |
| E2E-038 | Concurrent events for same customer | 50 POST /events simultaneously | Only matching waits triggered, no duplicates | P1 |

### 16.4 E2E Version Migration

| ID | Test Case | Scenario | Expected | Priority |
|----|-----------|----------|----------|----------|
| E2E-040 | Live migration via API | 1. Create flow v1, activate, trigger 10 instances → 2. Create v2 → 3. POST migrate (migrate_all) → 4. Verify instances on v2 | All 10 migrated, execution continues | P0 |
| E2E-041 | Rollback via API | After E2E-040, POST rollback to v1 | Instances back on v1 | P0 |
| E2E-042 | New entries only migration | migrate with "new_entries_only" → trigger new customer | Old on v1, new on v2 | P0 |

### 16.5 E2E AI Chat

| ID | Test Case | Scenario | Expected | Priority |
|----|-----------|----------|----------|----------|
| E2E-050 | AI creates flow via chat | "Create a welcome email flow" → AI uses tools → flow created | Valid flow with correct nodes | P1 |
| E2E-051 | AI debugs instance | "Why is instance X stuck?" → AI analyzes | Relevant debug info returned | P2 |
| E2E-052 | Conversation persistence | Create conv → send messages → retrieve → same messages | Messages preserved | P1 |

---

## 17. Property-Based Tests

### 17.1 არსებული Property Tests (გასაფართოებელი)

| ID | Property | Generator | Invariant | Priority |
|----|----------|-----------|-----------|----------|
| P-001 | Valid DAG always passes validation | Random valid DAG | `FlowGraph.validate == :ok` | P0 |
| P-002 | Cyclic graph always fails | DAG + added back-edge | error includes "cycle" | P0 |
| P-003 | Orphan always detected | Valid graph + disconnected node | error includes "unreachable" | P0 |
| P-004 | State machine never invalid | Random command sequence | final state in valid_states | P0 |
| P-005 | Terminal states are terminal | completed/failed + any command | all return :invalid_transition | P0 |
| P-006 | State serialization round-trip | Random FlowState | serialize → deserialize == original | P0 |
| P-007 | Event routing matches | Random customer/event | registered waits always receive | P0 |
| P-008 | Unregistered never receives | Random dispatch, no registration | no message received | P0 |
| P-009 | Frequency cap never exceeded | Random send pattern | allowed <= max | P0 |
| P-010 | A/B split deterministic | Same customer_id | same variant always | P0 |
| P-011 | A/B distribution matches weights | 10K customers | within ±5% of weights | P0 |
| P-012 | Condition node symmetry | equals/not_equals same input | opposite branches | P0 |
| P-013 | Duration parse round-trip | Random duration string | parse → format == original | P1 |
| P-014 | NodeMapper completeness | Random old/new graphs | every old node mapped or marked | P0 |
| P-015 | Migration safety detection | Graphs with removed nodes | always flagged as warning | P0 |
| P-016 | Wait change detection | Modified wait configs | always detected | P0 |
| P-017 | Tenant isolation | Random tenant pairs | queries never cross boundaries | P0 |
| P-018 | Context accumulation | N-node linear flow | accumulated has N entries | P1 |
| P-019 | Graph entry nodes | Random graph | at least 1 trigger node found | P0 |
| P-020 | Concurrent trigger dedup | Same customer+flow, parallel | at most 1 instance created | P1 |

---

## 18. Bug Regression Tests — არსებული და დასამატებელი

### 18.1 არსებული (21 ფაილი)

| File | Bug Description | Status |
|------|----------------|--------|
| ab_split_empty_variants_test | Empty variants crash | ✅ Covered |
| cross_tenant_event_test | Events leaking across tenants | ✅ Covered |
| exit_node_parallel_queue_test | Exit in parallel group deadlock | ✅ Covered |
| frequency_cap_branching_test | Freq cap wrong branch | ✅ Covered |
| instance_status_transition_test | Invalid status transitions | ✅ Covered |
| invalid_migration_strategy_test | Unknown migration strategy crash | ✅ Covered |
| nil_customer_id_test | Nil customer_id in trigger | ✅ Covered |
| recovery_trigger_mismatch_test | Recovery starts wrong trigger | ✅ Covered |
| republish_validation_test | Re-publishing already published | ✅ Covered |
| resume_failed_branch_test | Resume on failed branch path | ✅ Covered |
| resume_job_dead_process_test | Resume job targets dead process | ✅ Covered |
| rollback_invalid_target_test | Rollback to non-existent version | ✅ Covered |
| same_version_migration_test | Migrate to current version | ✅ Covered |
| wait_until_migration_test | Wait config change during migration | ✅ Covered |

### 18.2 დასამატებელი Regression Tests

| ID | Bug Scenario | Description | Priority |
|----|-------------|-------------|----------|
| BUG-022 | Concurrent migration + new entry | New customer enters during migration, gets wrong version | P0 |
| BUG-023 | Memory leak on long-running wait | FlowServer accumulates context without cleanup | P1 |
| BUG-024 | Unicode in template interpolation | `{{name}}` with Georgian/Chinese characters | P1 |
| BUG-025 | Large context serialization | Context > 1MB causes DB write timeout | P1 |
| BUG-026 | Orphaned Oban jobs after cancellation | Instance cancelled but resume job still fires | P0 |
| BUG-027 | Race condition in event routing | Two events arrive < 1ms apart for same wait | P0 |
| BUG-028 | Null pointer in nested condition | `condition.field: "props.x.y"` where `props.x` is nil | P0 |
| BUG-029 | Timezone mismatch in wait_until | UTC vs tenant timezone | P1 |
| BUG-030 | API key hash collision | Extremely unlikely but handle gracefully | P2 |

---

## 19. არქიტექტურული სქემა — ტესტების დაფარვის რუკა

```
                                    ┌─────────────────┐
                                    │   E2E Tests      │
                                    │   (38 cases)     │
                                    └────────┬────────┘
                                             │
                        ┌────────────────────┼────────────────────┐
                        │                    │                    │
               ┌────────▼────────┐  ┌────────▼────────┐  ┌───────▼────────┐
               │  API Controller  │  │   Integration    │  │   WebSocket    │
               │  Tests (70+)     │  │   Tests (25+)    │  │   Tests (5)    │
               └────────┬────────┘  └────────┬────────┘  └───────┬────────┘
                        │                    │                    │
         ┌──────────────┴──────────────┬─────┴─────┬──────────────┘
         │              │              │           │
  ┌──────▼──────┐ ┌─────▼──────┐ ┌────▼────┐ ┌────▼─────┐
  │   Flows     │ │  Marketing │ │Customers│ │ Channels │
  │  (30+ unit) │ │  (20+ unit)│ │(20+ unit│ │ (15+ unit│
  └──────┬──────┘ └────────────┘ └─────────┘ └──────────┘
         │
  ┌──────▼─────────────────────────────────────────────┐
  │                    Engine Core                      │
  │  FlowServer(15) + NodeExec(6) + GraphWalker(9)     │
  │  EventRouter(5) + Recovery(6) + Trigger(4)         │
  │  CircuitBreaker(7) + Duration(8)                   │
  └──────┬─────────────────────────────────────────────┘
         │
  ┌──────▼─────────────────────────────────────────────┐
  │                    Node System                      │
  │  Trigger(7) + Channel(18) + Data(12) + AI(14)      │
  │  Condition(26) + Wait(10) + End(4) + Orch(7)       │
  └──────┬─────────────────────────────────────────────┘
         │
  ┌──────▼──────────┐  ┌───────────────────┐
  │  Persistence    │  │  Versioning        │
  │  (14 unit)      │  │  (12 unit + 4 prop)│
  └─────────────────┘  └───────────────────┘

  ┌────────────────────┐  ┌──────────────────┐
  │  Property Tests    │  │  Bug Regressions │
  │  (20 properties)   │  │  (30 cases)      │
  └────────────────────┘  └──────────────────┘
```

---

## 20. პრიორიტეტები და შესრულების გეგმა

### 20.1 რაოდენობრივი შეჯამება

| კატეგორია | არსებული | დასამატებელი | სულ სამიზნე |
|-----------|---------|-------------|------------|
| Unit Tests | ~700 | ~150 | ~850 |
| Integration Tests | ~80 | ~30 | ~110 |
| E2E Tests | 0 | ~38 | ~38 |
| Property Tests | ~7 | ~13 | ~20 |
| Bug Regressions | ~80 | ~9 | ~89 |
| WebSocket Tests | 0 | ~5 | ~5 |
| **სულ** | **~867** | **~245** | **~1112** |

### 20.2 ფაზები

#### ფაზა 1: კრიტიკული Gaps (1-2 კვირა)
- E2E ტესტების ინფრასტრუქტურის შექმნა (test helpers, API client)
- E2E-001 through E2E-003 (core lifecycle)
- E2E-030 through E2E-035 (error cases)
- P-001 through P-009 (core properties)
- BUG-026, BUG-027, BUG-028 (critical regressions)

#### ფაზა 2: სრული E2E დაფარვა (2-3 კვირა)
- E2E-010 through E2E-020 (complex flows)
- E2E-040 through E2E-042 (migration)
- WebSocket tests WS-001 through WS-005
- Missing integration tests (I-ENGINE-*, I-CROSS-*)

#### ფაზა 3: Property Tests & Edge Cases (1-2 კვირა)
- P-010 through P-020 (advanced properties)
- E2E-036 through E2E-038 (edge cases)
- E2E-050 through E2E-052 (AI chat)
- Remaining bug regressions

#### ფაზა 4: Performance & Chaos (მიმდინარე)
- Chaos test infrastructure
- Load test suite
- Reliability report automation

### 20.3 ტესტ ფაილების სტრუქტურა

```
test/
├── kalcifer/                          # Unit + Domain tests (არსებული)
│   ├── flows_test.exs
│   ├── marketing_test.exs
│   ├── customers_test.exs
│   ├── tenants_test.exs
│   ├── analytics_test.exs
│   ├── audit_test.exs
│   ├── engine/                        # Engine unit tests
│   ├── bugs/                          # Bug regressions
│   ├── versioning/                    # Versioning tests
│   └── ai/                            # AI subsystem tests
├── kalcifer_web/                      # Controller tests (არსებული)
│   ├── controllers/
│   └── plugs/
├── integration/                       # Cross-domain integration (გასაფართოებელი)
│   ├── trigger_to_completion_test.exs
│   ├── live_migration_test.exs
│   ├── multi_tenant_isolation_test.exs       # NEW
│   ├── frequency_cap_cross_flow_test.exs     # NEW
│   ├── analytics_pipeline_test.exs           # NEW
│   └── webhook_delivery_cycle_test.exs       # NEW
├── e2e/                               # End-to-end API tests (NEW)
│   ├── support/
│   │   ├── api_client.ex              # HTTP client helper
│   │   └── flow_fixtures.ex           # Predefined flow graphs
│   ├── flow_lifecycle_e2e_test.exs
│   ├── journey_lifecycle_e2e_test.exs
│   ├── complex_flows_e2e_test.exs
│   ├── error_handling_e2e_test.exs
│   ├── migration_e2e_test.exs
│   └── ai_chat_e2e_test.exs
├── property/                          # Property-based tests (NEW)
│   ├── flow_graph_property_test.exs
│   ├── state_machine_property_test.exs
│   ├── event_routing_property_test.exs
│   ├── frequency_cap_property_test.exs
│   ├── condition_node_property_test.exs
│   └── tenant_isolation_property_test.exs
├── chaos/                             # Chaos tests (FUTURE)
│   ├── process_kill_test.exs
│   ├── db_disconnect_test.exs
│   └── concurrent_stress_test.exs
└── load/                              # Load tests (FUTURE)
    └── concurrent_flows_test.exs
```

---

## 21. ხელსაწყოები და ინფრასტრუქტურა

### 21.1 ტესტირების Stack

| ხელსაწყო | დანიშნულება | სტატუსი |
|-----------|------------|---------|
| ExUnit | Test framework | ✅ აქტიური |
| ExMachina | Test factories | ✅ აქტიური |
| Mox | Mock/stub | ✅ აქტიური |
| StreamData | Property-based testing | ✅ ნაწილობრივ |
| Ecto SQL Sandbox | DB isolation per test | ✅ აქტიური |
| Oban.Testing | Job queue testing | ✅ manual mode |
| Req.Test | HTTP client mocking | 📋 დასამატებელი E2E-სთვის |
| Benchee | Performance benchmarks | 📋 დასამატებელი |

### 21.2 CI Integration

```yaml
# Recommended CI steps
- mix test --trace                           # Unit + Integration
- mix test test/e2e --trace                  # E2E (separate DB)
- mix test test/property --trace             # Property tests
- mix test --cover                           # Coverage report
```

### 21.3 Coverage Targets

| მეტრიკა | მიმდინარე (სავარაუდო) | სამიზნე |
|----------|---------------------|---------|
| Line coverage | ~75% | > 90% |
| Branch coverage | ~60% | > 80% |
| Domain coverage | 10/13 domains | 13/13 |
| E2E scenarios | 0 | 38+ |
| Property scenarios | ~100 | 500+ |

---

## 22. Appendix: Test Case ID Convention

```
{Type}-{Domain}-{Number}

Type:
  U    = Unit Test
  I    = Integration Test
  E2E  = End-to-End Test
  P    = Property-Based Test
  BUG  = Bug Regression
  WS   = WebSocket Test
  PERF = Performance Test

Domain:
  FLOW    = Flows Context
  ENGINE  = Engine Core
  NODE    = Node System
  PERSIST = Persistence
  MKT     = Marketing
  CUST    = Customers
  CHAN     = Channels
  ANLX    = Analytics
  TENANT  = Tenants & Auth
  API     = API Layer
  VER     = Versioning
  AI      = AI Subsystem
  AUDIT   = Audit
  CROSS   = Cross-Domain
```
