# Kalcifer — Status & Plan (2026-03-24)

## 1. რა გაკეთდა (Completed)

### Agent Activity Visibility — "კალციფერი რას აკეთებს?" (DONE)

**Engine-First Dogfooding:** ჩატის მესიჯის დამუშავება Flow Engine-ით ხდება.

**Backend:**
- `agent` node type (`lib/kalcifer/engine/nodes/action/ai/agent.ex`) — multi-round `chat_with_tools` as NodeBehaviour, PubSub broadcasts for real-time streaming
- AI Helpers extracted (`lib/kalcifer/engine/nodes/action/ai/helpers.ex`) — `build_messages`, `interpolate`, `summarize_context` shared between ai_think/ai_decide/agent
- `AgentFlows` (`lib/kalcifer/ai/agent_flows.ex`) — sentinel flow management per tenant
  - `ensure_simple_flow/1`: [webhook_entry] → [agent] → [exit]
  - `ensure_council_flow/1`: [entry] → [dreamer] → [realist] → [skeptic] → [synthesizer] → [executor] → [exit]
- `EventBroadcaster` extended — `broadcast_agent_text_delta/tool_start/tool_done/done` for instance-level broadcasting
- `ChatController` refactored — FlowServer-based execution with PubSub receive loop, direct chat fallback on engine failure
- `classify_session` SSE event emitted on engine path
- Sentinel flows filtered from `list_flows` tool
- `ClientBehaviour` extended with `chat_with_tools` callback for mock testing
- `NodeRegistry`: "agent" registered (now 24 built-in nodes)

**Frontend:**
- `AgentActivity` / `AgentActivityStep` types with tool sub-list support
- SSE events: `activity_start`, `activity_step`, `activity_done`
- `ActivityIndicator` component — collapsed/expanded views, Georgian labels, tool chips per step
- ChatPanel integration — activity wiring, replaces tool badges when activity present

**Tests:**
- 14 tests for agent node (dry_run, tool tracking, PubSub broadcasts, system prompt, error handling)
- 7 tests for AgentFlows (simple + council flow creation, idempotency, tenant isolation)
- 10 tests for AI Helpers (interpolation, context summarization, message building)

### Simulation Mode (DONE)

**Backend:**
- `POST /api/v1/flows/:flow_id/simulate` — SSE streaming simulation endpoint
- `SimulationController` subscribes to PubSub, forwards engine events as `sim_start/sim_step/sim_done`
- Supports draft flows (latest version) and active flows
- Reuses existing dry_run infrastructure (all 23 nodes already handle `_dry_run` context)

**Frontend:**
- `simulateFlow()` API function with SSE parsing
- FlowEditorPage: simulation controls (Dry Run / Stop / Reset / Re-run) in bottom bar
- FlowCanvas: `simCompletedNodes` + `simActiveNode` props for node highlighting
- FlowNode: simulation badges (checkmark/active indicator) and dynamic border coloring
- CSS: `simPulse` animation, sim-active/sim-completed states

### Graph Cycles + Council Flow (DONE)

**Engine:**
- `FlowGraph.validate/2` accepts `allow_cycles: true` option
- `FlowServer`: `max_node_executions` (200) guard prevents infinite loops
- `node_execution_count` field tracks total nodes executed per instance

**Council Flow Template:**
- 7-node deliberation flow: entry → dreamer → realist → skeptic → synthesizer → executor → exit
- Each persona = ai_think node with role-specific prompts
- Prompts use `{{accumulated.node_id.response}}` interpolation for context passing
- Synthesizer integrates all perspectives, executor (agent node) acts on recommendation

### Browse Page — Instances Panel (DONE)
- `InstanceBrowseController` — unauthenticated instance endpoints for dev frontend
- BrowsePage Instances panel: flow selector, instance table with status badges
- Timeline viewer: numbered steps, node type, duration, expandable output JSON
- Instance API functions: `fetchInstances`, `fetchInstance`, `fetchInstanceTimeline`

### Council Flow in Chat (DONE)
- ChatController selects between simple and council flows based on keywords
- Keywords: "საბჭო", "დაფიქრდი", "council", "ანალიზი" → council flow
- ActivityIndicator shows Georgian persona labels (ოცნებისმყრელი, რეალისტი, სკეპტიკოსი, სინთეზატორი)

### Graph Save in Editor (DONE)
- `convertReactFlowToGraph` — reverse conversion ReactFlow → backend FlowGraph
- Save button in topbar + Ctrl+S keyboard shortcut
- `hasChanges` tracking, save button highlights when unsaved changes exist
- Uses `PUT /flows/:id/versions/:v` endpoint

### Multi-Provider AI Client (previous sprint)
- `lib/kalcifer/ai/client.ex` — Anthropic/OpenAI/Google routing
- Provider adapters: `providers/anthropic.ex`, `providers/openai.ex`, `providers/google.ex`
- OpenAI tool_call format fix, Gemini streaming

### Flow Editor (previous sprint)
- `FlowCanvas.tsx` reusable component, `FlowEditorPage.tsx` standalone editor
- `NodePalette`, `NodeConfigPanel`, `FlowNode` components
- WorkPage 5-stage layout system
- ChatPanel → Context Area signal for flow visualization

---

## 2. შემდეგი ნაბიჯები (Next Sprint)

### 2.1 Undo/Redo + Editor Keyboard Shortcuts (DONE)
- Undo/redo stack via `useUndoRedo` hook (max 50 snapshots)
- Ctrl+Z undo, Ctrl+Y / Ctrl+Shift+Z redo
- Delete/Backspace removes selected nodes + connected edges
- Snapshots before structural changes (add/remove/connect)
- 8 tests for useUndoRedo hook

### 2.2 Validation Overlay (DONE)
- `preflightFlow` API call + `parseNodeWarnings` utility
- Warning badge (⚠ N) on nodes with tooltip showing issues
- "Validate" button in editor topbar
- Warnings auto-clear on graph changes
- 3 tests for parseNodeWarnings

### 2.3 Live Mode (DONE — basic)
- FlowChannel subscribes to PubSub, pushes engine events to WebSocket clients
- `useFlowSocket` hook: Phoenix WebSocket client for `flow:*` topic
- Tracks active instances, completed/active nodes per instance
- Canvas highlights nodes in real-time during flow execution
- Bottom bar: connection status + active instance count

**TODO (enhancement):**
- Instance timeline overlay (select specific instance to track)
- Node-level analytics (conversion rates, avg execution time)

### 2.4 Backend Recompilation
ყველა Elixir ცვლილება საჭიროებს:
```bash
docker compose -f docker-compose.dev.yml restart app
```

---

## 3. სამომავლო დიდი თემები (Roadmap)

### Theme A: Cognitive Architecture Expansion
- [ ] Parallel nodes: `parallel_group` node type (Task.async_stream in FlowServer)
- [ ] Sub-flows: `sub_flow` node type (child FlowInstance)
- [ ] Dynamic flow selection: intake ai_decide → simple vs complex flow
- [ ] Memory integration: long-term memory as node input
- [ ] Multi-model support: different models for different council personas

### Theme B: Editor Full Features
- [x] Graph save: canvas → FlowGraph → `PUT /flows/:id/versions/:v`
- [x] Undo/redo: Ctrl+Z / Ctrl+Y (snapshot-based)
- [x] Delete shortcut: Delete/Backspace
- [x] Validation overlay: preflight warnings on nodes
- [ ] Edge labels with branch conditions
- [ ] Copy/paste nodes
- [ ] Node groups / subflows

### Theme C: Debugging & Observability
- [x] Live mode: running instance real-time tracking on canvas
- [ ] Instance timeline overlay — execution path visualization
- [ ] Node-level analytics (conversion rates, avg time)
- [ ] Error highlighting on failed nodes

### Theme D: AI-Assisted Flow Building
- [ ] Chat → flow generation: "build me an onboarding flow" → auto-creates graph
- [ ] Chat → node editing: "change the wait to 3 days" → updates specific node
- [ ] AI suggestions: "this condition has no false branch"
- [ ] Natural language condition builder

### Theme E: Channel Integration
- [ ] Provider configuration UI (SendGrid, Twilio, Firebase)
- [ ] Email template editor (inline or linked)
- [ ] SMS preview
- [ ] Delivery status tracking

### Theme F: Multi-tenancy & Production
- [ ] API key management UI
- [ ] Tenant switching
- [ ] Rate limiting
- [ ] Audit log
- [ ] Export/import flows

---

## ფაილური რუკა (Key Files Map)

```
## Backend (Elixir)
lib/kalcifer/ai/
  client.ex                    # Multi-provider AI client
  client_behaviour.ex          # Behaviour (chat + chat_with_tools)
  providers/{anthropic,openai,google}.ex  # Provider adapters
  tools.ex                     # AI tool definitions + UUID validation
  agent_flows.ex               # Agent flow templates (simple, council)

lib/kalcifer/engine/
  flow_server.ex               # GenServer per instance (max_node_executions guard)
  event_broadcaster.ex         # PubSub broadcasts (+ agent-specific events)
  node_registry.ex             # 24 built-in nodes (includes "agent")
  nodes/action/ai/
    agent.ex                   # Multi-round chat_with_tools node
    helpers.ex                 # Shared AI helpers (interpolate, build_messages)
    think.ex                   # Single LLM call node
    decide.ex                  # AI branching node
    notify.ex                  # Operator notification node

lib/kalcifer_web/
  router.ex                    # Routes (+ /simulate endpoint)
  controllers/
    chat_controller.ex         # FlowServer-based chat with PubSub receive loop
    simulation_controller.ex   # Dry-run simulation SSE streaming
    instance_browse_controller.ex # Unauthenticated instance browsing
    flow_controller.ex         # Flow CRUD
    flow_version_controller.ex # Version CRUD

lib/kalcifer/flows/
  flow_graph.ex                # Graph validation (allow_cycles option)

## Frontend (React + TypeScript)
frontend/src/
  App.tsx                      # Routes: /, /engine, /browse, /editor
  lib/
    api.ts                     # API client (+ simulation, activity, instance SSE)
    chat.ts                    # Types (ChatMessage, AgentActivity, AgentActivityStep)
  components/
    FlowCanvas.tsx             # Reusable ReactFlow canvas (+ sim highlighting)
    flow-canvas.css            # Canvas + node + simulation styles
    ChatPanel.tsx              # Chat with activity wiring
    ActivityIndicator.tsx      # Agent activity indicator (collapsed/expanded)
    activity-indicator.css     # Activity styles
  pages/
    WorkPage.tsx               # 5-stage work page
    BrowsePage.tsx             # Flows + Instances panels with timeline
    editor/
      FlowEditorPage.tsx       # Editor with simulation controls + graph save
      FlowNode.tsx             # Node component (+ simulation badges)
      NodePalette.tsx          # Draggable node palette
      NodeConfigPanel.tsx      # Node configuration panel
      nodeTypes.ts             # 21 node types metadata
      flowGraphUtils.ts        # Shared graph utilities (+ convertReactFlowToGraph)

## Tests
test/kalcifer/engine/nodes/action/ai/
  agent_test.exs               # 14 tests for agent node
  helpers_test.exs             # 10 tests for AI helpers
test/kalcifer/ai/
  agent_flows_test.exs         # 7 tests for agent flow templates
```
