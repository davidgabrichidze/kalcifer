# Kalcifer — Status & Plan (2026-03-23)

## 1. რა გაკეთდა (Completed)

### Multi-Provider AI Client
- `lib/kalcifer/ai/client.ex` — რეფაქტორინგი: Anthropic-only → multi-provider routing
- ახალი adapter მოდულები: `providers/anthropic.ex`, `providers/openai.ex`, `providers/google.ex`
- Provider auto-detection მოდელის სახელიდან (gpt→openai, gemini→google, claude→anthropic)
- OpenAI tool_call format fix: `process_tool_calls` string-keyed maps, `Enum.flat_map` for tool results
- Gemini streaming: `:streamGenerateContent?alt=sse` endpoint

### UUID Validation (AI Tools)
- `lib/kalcifer/ai/tools.ex` — `validate_uuid_fields/2` prevents Ecto crashes when AI hallucinates placeholder IDs
- Error message guides AI back: "must be a real UUID, not a placeholder"

### Flow Editor — ფუნდამენტი + WorkPage ინტეგრაცია
**ექსტრაქცია და რეუტილიზაცია:**
- `frontend/src/pages/editor/flowGraphUtils.ts` — shared pure ფუნქციები: `autoLayoutNodes`, `summarizeNodeConfig`, `convertGraphToReactFlow`
- `frontend/src/components/FlowCanvas.tsx` — reusable ReactFlow canvas კომპონენტი (`FlowCanvasProps`: flowGraph, editable, onGraphChange, onNodeSelect, showMiniMap, showControls)
- `frontend/src/components/flow-canvas.css` — canvas + node + handle სტილები (editor.css-დან ექსტრაქცია)

**Standalone editor (შენარჩუნებული `/editor` route):**
- `frontend/src/pages/editor/FlowEditorPage.tsx` — ახლა FlowCanvas-ს იყენებს, topbar/chat/palette/config/bottombar შენარჩუნებული
- `frontend/src/pages/editor/FlowNode.tsx` — custom node component, category-based colors, branching handles
- `frontend/src/pages/editor/NodePalette.tsx` — drag-enabled node palette
- `frontend/src/pages/editor/NodeConfigPanel.tsx` — type-specific config panel
- `frontend/src/pages/editor/nodeTypes.ts` — 21 node type metadata
- `frontend/src/pages/editor/editor.css` — editor chrome styles (topbar, bottombar, palette, config)

**WorkPage Stage System (5 stages):**
- `frontend/src/pages/WorkPage.tsx` — stage: `welcome | lobby | chat | split | context`
- `frontend/src/pages/work-stages.css` — data-stage CSS selectors:
  - welcome: full-width centered, no sidebar, no context
  - lobby: sidebar visible, centered welcome
  - chat: sidebar + dominant chat, no context
  - split: chat (flex:1, max 480px) + context (flex:2) side-by-side
  - context: compact chat (340px fixed) + full context (flex:3)
- Generic `ContextContent` discriminated union: `{ type: 'flow-canvas'; flowGraph } | null`
  - მომავალში: `'report'`, `'analytics'` და სხვა ტიპები
- Context area header: expand/collapse (⤢/⤡) + close (✕) ღილაკები
- Stage transitions: chat→split ავტომატურად tool result-ით, split↔context toggle-ით

**ChatPanel → Context Area სიგნალი:**
- `ChatPanel.tsx` — `onContextContent` prop, flow tool result-ებიდან graph-ის ავტო-დეტექცია
- Tool badge-ზე "⤢ გახსნა" ღილაკი — მომხმარებელს ხელით შეუძლია context area-ში გახსნა
- Flow tools: `create_flow`, `get_flow_graph`, `add_node`, `modify_node`

### Backend (Dev Frontend Support)
- `lib/kalcifer_web/router.ex` — unauthenticated GET routes: `/flows`, `/flows/:id`, `/flows/:flow_id/versions`, `/flows/:flow_id/versions/:version_number`
- `FlowController.fetch_tenant_flow` — `resolve_tenant(conn)` fallback (Demo Tenant for dev)
- `FlowVersionController` — same resolve_tenant pattern

### Browse Page → Editor Navigation
- `frontend/src/pages/BrowsePage.tsx` — flow name clickable → `/editor?flow=${id}`, ✎ edit button

---

## 2. მიმდინარე / შემდეგი ნაბიჯები (Current Sprint)

### 2.1 Agent Activity Visibility — "კალციფერი რას აკეთებს?" (პრიორიტეტი #1)

**პრობლემა:** მომხმარებელს არ ესმის კალციფერი (როგორც agentic AI) ბეგრაუნდში რას ფიქრობს და რას აკეთებს. ჩატის typing indicator არ არის საკმარისი — საჭიროა AI-ის "სამუშაო პროცესის" ვიზუალიზაცია.

**ეს არ ეხება ჩატს.** ჩათი (messaging) გასაგებია. ეს ეხება კალციფერის, როგორც აგენტის, სამუშაო ციკლს: tool calls, reasoning, multi-step operations.

**მთავარი იდეა:** კალციფერის საკუთარი workflow engine-ის გამოყენება AI agent-ის სამუშაო პროცესის ვიზუალიზაციისთვის ("dogfooding"). AI-ის სამუშაო ციკლი (think → plan → tool_call → evaluate → respond) თავად არის flow, რომელიც Kalcifer-ის engine-ით შეიძლება იყოს ორკესტრირებული და მონიტორინგირებული.

**რა უნდა გაკეთდეს:**
1. AI agent-ის სამუშაო ციკლის მოდელირება flow-ად (thinking, planning, tool execution, evaluation)
2. Real-time activity feed / progress indicator UI — არა ჩატში, არამედ ცალკე ვიზუალი
3. მომხმარებელმა უნდა ხედოს: "კალციფერი ახლა ფლოუს ქმნის... 3/5 ნოდი დამატებულია" ან "ანალიზს აკეთებს..."
4. Workflow engine-ის integration: agent steps → FlowInstance → real-time tracking

**საკვანძო კითხვები შემდეგი სესიისთვის:**
- სად ჩანს activity indicator? (context area-ში? topbar-ში? floating panel?)
- რამდენად დეტალური? (high-level status vs step-by-step)
- Backend: SSE/WebSocket for real-time updates vs polling?
- Engine integration: FlowServer-ის გამოყენება AI workflow tracking-ისთვის

### 2.2 Simulation Mode (პრიორიტეტი #2)
პროტოტიპში (`ui-prototype/flow-editor.html`) simulation აქვს: dry run, step-by-step, badges, log.

**რა უნდა გაკეთდეს:**
1. Simulation state machine: `idle → running → paused → completed → failed`
2. Backend endpoint: `POST /api/v1/flows/:flow_id/simulate` — dry run execution without side effects
3. Step-by-step UI: highlight current node, show execution path, display context at each step
4. `.sim-badge` on nodes showing execution status (pending/active/completed/failed)
5. Simulation log panel (bottom or side)
6. Bottom bar buttons: Dry Run / Step / Stop

**Backend needs:**
- `FlowServer` dry-run mode — execute nodes but skip actual channel delivery
- Simulation state tracking endpoint
- WebSocket for real-time step updates (optional, SSE fallback)

### 2.3 Backend Recompilation
ყველა Elixir ცვლილება (`client.ex`, `tools.ex`, `flow_controller.ex`, `flow_version_controller.ex`, `router.ex`) საჭიროებს:
```bash
docker compose -f docker-compose.dev.yml restart app
```

---

## 3. სამომავლო დიდი თემები (Roadmap)

### Theme A: Editor Full Features
- [ ] Graph save: canvas → FlowGraph → `PUT /flows/:id/versions/:v` (undo/redo)
- [ ] Validation overlay: preflight warnings ნოდებზე
- [ ] Edge labels with branch conditions
- [ ] Copy/paste nodes
- [ ] Node groups / subflows
- [ ] Keyboard shortcuts (Delete, Ctrl+Z, Ctrl+S)

### Theme B: Debugging & Observability
- [ ] Live mode: running instance-ების real-time tracking canvas-ზე
- [ ] Instance timeline overlay — execution path visualization
- [ ] Node-level analytics (conversion rates, avg time)
- [ ] Error highlighting on failed nodes

### Theme C: AI-Assisted Flow Building
- [ ] Chat → flow generation: "build me an onboarding flow" → auto-creates graph
- [ ] Chat → node editing: "change the wait to 3 days" → updates specific node
- [ ] AI suggestions: "this condition has no false branch"
- [ ] Natural language condition builder

### Theme D: Channel Integration
- [ ] Provider configuration UI (SendGrid, Twilio, Firebase)
- [ ] Email template editor (inline or linked)
- [ ] SMS preview
- [ ] Delivery status tracking

### Theme E: Multi-tenancy & Production
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
  providers/{anthropic,openai,google}.ex  # Provider adapters
  tools.ex                     # AI tool definitions + UUID validation

lib/kalcifer_web/
  router.ex                    # Unauthenticated + authenticated routes
  controllers/
    flow_controller.ex         # Flow CRUD + resolve_tenant fallback
    flow_version_controller.ex # Version CRUD + resolve_tenant fallback

## Frontend (React + TypeScript)
frontend/src/
  App.tsx                      # Routes: /, /engine, /browse, /editor
  components/
    FlowCanvas.tsx             # Reusable ReactFlow canvas (used in editor + WorkPage)
    flow-canvas.css            # Canvas + node styles (shared)
    ChatPanel.tsx              # Chat with onContextContent callback
    Sidebar.tsx                # Conversation sidebar
    WelcomeScreen.tsx          # Welcome/onboarding screen
  pages/
    WorkPage.tsx               # 5-stage work page (welcome/lobby/chat/split/context)
    work-stages.css            # Stage layout CSS (data-stage selectors)
    BrowsePage.tsx             # Flow listing with editor navigation
    editor/
      FlowEditorPage.tsx       # Standalone editor (composes FlowCanvas)
      FlowNode.tsx             # Custom React Flow node component
      NodePalette.tsx          # Draggable node palette
      NodeConfigPanel.tsx      # Node configuration panel
      nodeTypes.ts             # 21 node types metadata
      flowGraphUtils.ts        # Shared: autoLayout, summarize, convertGraph
      editor.css               # Editor chrome styles (topbar, bottombar, palette, config)
  lib/api.ts                   # API client (flow, version, conversation, settings)

## Prototypes (reference only)
ui-prototype/
  main.html                    # Stage system: welcome/chat/split/context
  flow-editor.html             # Editor prototype with simulation
  engine-room.html             # Engine dashboard prototype
  browse.html                  # Browse prototype
```
