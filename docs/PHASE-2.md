# Phase 2: Frontend & AI — კალციფერის გაცოცხლება

> **სტატუსი**: 📋 დაგეგმილი
> **წინაპირობა**: Phase 1 ✅ დასრულებული (553 tests, 0 failures, CI green)
> **ხედვა**: AI-First — კალციფერი სახლის გულია, ის ამუშავებს ყველაფერს, ცოცხალია

---

## არქიტექტურული ხედვა

```
┌─────────────────────────────────────────────────────┐
│                  React SPA (Vite)                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ AI Chat  │  │  Canvas  │  │  Engine Room     │  │
│  │ (Core)   │◄─┤  Editor  │  │  (Monitoring)    │  │
│  └────┬─────┘  └────┬─────┘  └────────┬─────────┘  │
│       │              │                 │             │
│  ┌────▼──────────────▼─────────────────▼─────────┐  │
│  │           Shared State (Zustand)              │  │
│  │   flows · instances · theme · ai · websocket  │  │
│  └────────────────────┬──────────────────────────┘  │
└───────────────────────┼──────────────────────────────┘
                        │
         ┌──────────────┼──────────────┐
         │              │              │
    ┌────▼────┐   ┌─────▼─────┐  ┌────▼────┐
    │ REST    │   │ WebSocket │  │ AI      │
    │ API     │   │ (Phoenix  │  │ Proxy   │
    │ /api/v1 │   │ Channels) │  │ /ai/... │
    └────┬────┘   └─────┬─────┘  └────┬────┘
         │              │              │
    ┌────▼──────────────▼──────────────▼────┐
    │        Kalcifer Engine (Elixir)        │
    │   Flows · Channels · Analytics · AI   │
    └───────────────────────────────────────┘
```

### AI არა feature-ა — ბირთვია

კალციფერი = Calcifer (Howl's Moving Castle). სახლის ცეცხლი, გული.
AI არ არის sidebar-ის chatbot. AI არის primary interface:

1. **Flow Creation**: "შემიქმენი onboarding flow 3 ნაბიჯით" → AI generates flow graph
2. **Flow Analysis**: AI ხედავს analytics-ს და რეკომენდაციას იძლევა
3. **Debugging**: "რატომ ჩავარდა ეს instance?" → AI analyzes execution steps
4. **Optimization**: AI suggests A/B variants, timing changes, content improvements
5. **Natural Language → Config**: ტექსტი → node configuration JSON

---

## ტექნოლოგიური სტეკი

| Layer | Technology | Reason |
|-------|-----------|--------|
| Framework | React 19 + Vite 6 | სწრაფი dev, HMR, tree-shaking |
| Routing | React Router 7 | SPA navigation |
| State | Zustand | მსუბუქი, TypeScript-friendly |
| Styling | TailwindCSS 4 | Design tokens → utility classes |
| Canvas | React Flow (xyflow) | Production-grade flow editor |
| Charts | Recharts | React-native Chart.js alternative |
| AI Chat | Vercel AI SDK | Streaming, tool calls |
| WebSocket | Phoenix JS client | Real-time EventBroadcaster |
| HTTP | ky / fetch | Lightweight API client |
| Types | TypeScript 5.7 | Type safety everywhere |
| Testing | Vitest + Testing Library | Fast, React-optimized |
| Linting | ESLint + Prettier | Code quality |

---

## პროტოტიპიდან React-ში — კომპონენტების რუკა

### გვერდები (4 route)

| პროტოტიპი | React Route | აღწერა |
|-----------|-------------|--------|
| `main.html` | `/` | Work — AI chat + canvas + dashboard |
| `flow-editor.html` | `/flows/:id/edit` | Dedicated flow editor |
| `engine-room.html` | `/engine` | Operations monitoring |
| `browse.html` | `/browse` | Flow library |

### კომპონენტთა იერარქია

```
App
├── ThemeProvider (6 themes × 2 modes)
├── TopBar
│   ├── Logo
│   ├── Navigation (Work / Browse / Engine)
│   ├── ThemeSwitcher
│   └── UserAvatar
│
├── WorkPage (/)
│   ├── Sidebar
│   │   ├── NewFlowButton
│   │   ├── FlowList (active/archived sections)
│   │   └── TenantSelector
│   ├── ResizeHandle
│   ├── ChatPanel
│   │   ├── MessageList
│   │   │   ├── AIMessage (+ suggestions, code blocks)
│   │   │   └── UserMessage
│   │   ├── TypingIndicator
│   │   └── ChatInput
│   └── ContextPanel (dynamic)
│       ├── FlowCanvas (mini)
│       ├── DashboardView (metrics, charts, funnel)
│       ├── ABTestResults
│       └── LiveEventStream
│
├── FlowEditorPage (/flows/:id/edit)
│   ├── EditorTopBar (flow name, version, modes)
│   ├── ChatPanel (left, collapsible)
│   ├── FlowCanvas (center)
│   │   ├── ReactFlow (xyflow)
│   │   │   ├── TriggerNode
│   │   │   ├── ConditionNode
│   │   │   ├── WaitNode
│   │   │   ├── ActionNode
│   │   │   └── EndNode
│   │   ├── CustomEdge (bezier + labels)
│   │   ├── Minimap
│   │   └── ZoomControls
│   ├── NodePalette (right, collapsible)
│   ├── NodeConfigPanel (right, slide-in)
│   └── SimulationOverlay
│
├── EnginePage (/engine)
│   ├── EngineNav (left sidebar)
│   │   ├── StatusSection (active/paused/failed)
│   │   ├── ConnectorsSection
│   │   ├── InfraSection
│   │   └── HealthIndicator
│   ├── DashboardPanel
│   │   ├── StatCards (4-grid)
│   │   ├── PerformanceChart
│   │   ├── EventLog
│   │   └── FailedInstances
│   ├── ConnectorsPanel
│   ├── SettingsPanel
│   └── ChatPanel (right)
│
└── BrowsePage (/browse)
    ├── FilterSidebar
    ├── FlowGrid
    │   └── FlowCard (thumbnail, status, stats)
    └── ChatPanel (right, toggleable)
```

### საერთო კომპონენტები (shared/)

```
shared/
├── ChatPanel/           # AI chat — ყველა გვერდზე
│   ├── ChatPanel.tsx
│   ├── MessageList.tsx
│   ├── AIMessage.tsx    # Markdown, code, suggestions
│   ├── UserMessage.tsx
│   ├── ChatInput.tsx
│   └── TypingIndicator.tsx
├── FlowCanvas/          # React Flow wrapper
│   ├── FlowCanvas.tsx
│   ├── nodes/           # Custom node components
│   ├── edges/           # Custom edge components
│   └── Minimap.tsx
├── ui/                  # Base UI components
│   ├── Button.tsx
│   ├── Badge.tsx
│   ├── Card.tsx
│   ├── Input.tsx
│   ├── Select.tsx
│   ├── Modal.tsx
│   ├── Tooltip.tsx
│   ├── ResizeHandle.tsx
│   └── StatusDot.tsx
├── charts/              # Data visualization
│   ├── FunnelChart.tsx
│   ├── PerformanceChart.tsx
│   └── StatCard.tsx
└── theme/               # Theme system
    ├── ThemeProvider.tsx
    ├── tokens.ts        # CSS variables → TS
    └── themes.ts        # 6 theme definitions
```

---

## Increment-ები

### Increment 18: Project Setup & Design System
**Goal**: React project, TailwindCSS, theme system, base components

```
18a: Vite + React + TypeScript + TailwindCSS setup
18b: Design tokens → Tailwind config (6 themes)
18c: Base UI components (Button, Badge, Card, Input, etc.)
18d: TopBar + ThemeSwitcher + Router shell
```

**Deliverable**: აპლიკაცია იხსნება, თემები იცვლება, 4 ცარიელი გვერდი route-ებით

---

### Increment 19: AI Chat System (ბირთვი)
**Goal**: AI chat infrastructure — streaming, tool calls, flow generation

```
19a: Backend — AI proxy endpoint (/api/v1/ai/chat)
     - Elixir module: Kalcifer.AI.ChatHandler
     - Claude API integration (streaming SSE)
     - System prompt with Kalcifer context (node types, API schema)
     - Tool definitions: create_flow, add_node, simulate, analyze

19b: Frontend — ChatPanel component
     - Streaming message display
     - Markdown rendering (code blocks, tables)
     - Suggestion chips (clickable actions)
     - Message history (per-session)

19c: AI Tools — Flow Generation
     - create_flow tool: AI → flow graph JSON → API → canvas
     - add_node tool: AI adds node to existing flow
     - modify_node tool: AI updates node config
     - simulate tool: AI triggers dry run

19d: AI Tools — Analysis
     - analyze_flow tool: AI reads flow structure, suggests improvements
     - debug_instance tool: AI reads execution steps, explains failures
     - recommend tool: AI suggests optimizations based on analytics
```

**Deliverable**: ჩატში ეუბნები "შემიქმენი welcome email flow" → AI ქმნის flow-ს API-ით

---

### Increment 20: Flow Editor (Visual Canvas)
**Goal**: React Flow-based drag-drop editor with simulation

```
20a: React Flow integration
     - Custom nodes (5 categories × styling)
     - Custom edges (bezier + branch labels)
     - Drag from palette to canvas
     - Connection validation (type-compatible ports)

20b: Node Configuration
     - Config panel (slide-in right)
     - Type-specific forms (email: template, subject; wait: duration; etc.)
     - JSON editor (advanced mode)
     - Real-time validation

20c: Flow ↔ API sync
     - Load flow from API → render on canvas
     - Canvas changes → save to API (debounced)
     - Version management (draft/published)
     - Publish flow (preflight → activate)

20d: Simulation (Dry Run)
     - Step-through animation
     - Node badges (pass/skip/fail/waiting)
     - Edge highlighting
     - Execution log in chat
     - AI explains each step
```

**Deliverable**: სრული flow editor — drag-drop, config, save, publish, dry run

---

### Increment 21: Work Page (Main Orchestrator)
**Goal**: main.html → React — chat + canvas + dashboard

```
21a: Stage system (welcome → chat → split → context)
     - Responsive flex layout
     - Resize handle between panels
     - Stage transitions (animated)

21b: Sidebar
     - Flow list (active/archived)
     - Status dots (draft/active/paused/archived)
     - New flow button → AI chat
     - Session persistence

21c: Context Panel
     - Mini flow canvas (read-only, clickable → editor)
     - Dashboard metrics (Running/Waiting/Completed/Failed)
     - Execution funnel (Recharts)
     - A/B test results table

21d: Live Event Stream
     - WebSocket connection (Phoenix channels)
     - Real-time instance updates
     - Auto-scroll event log
```

**Deliverable**: მთავარი გვერდი — AI chat-ით flow-ს აშენებ, dashboard-ზე შედეგს ხედავ

---

### Increment 22: Engine Room (Monitoring)
**Goal**: engine-room.html → React — ops dashboard

```
22a: Engine navigation + panels
     - Left sidebar with status/connectors/infra sections
     - Panel switching (Dashboard/Flows/Events/Connectors/Settings)

22b: Dashboard
     - Stat cards (4-grid: instances, success rate, latency, throughput)
     - Performance chart (time-series, Recharts)
     - Failed instances list

22c: Real-time monitoring
     - WebSocket: live instance status
     - Event log stream
     - Connector health polling

22d: Connector management UI
     - Provider cards (SendGrid, Twilio, Webhook, Log)
     - Simulator controls (send test message)
     - Status indicators (connected/error/pending)
```

**Deliverable**: Engine Room — real-time monitoring, connector simulators

---

### Increment 23: Browse Page & Polish
**Goal**: browse.html → React + overall UX polish

```
23a: Browse page
     - Filter sidebar (All/Recent/Starred/Templates/Archived)
     - Flow grid cards with thumbnails
     - Click → navigate to editor or work page

23b: Provider Simulators
     - LogProvider UI: message log viewer
     - WebhookProvider UI: HTTP request/response viewer
     - Email simulator: rendered template preview
     - SMS simulator: phone mockup

23c: Georgian + English i18n
     - i18next setup
     - Georgian translations
     - Language switcher

23d: Final polish
     - Loading states (skeletons)
     - Error boundaries
     - Keyboard shortcuts
     - Mobile-responsive adjustments
     - Accessibility (a11y)
```

**Deliverable**: სრული production-ready frontend

---

## AI System Architecture (Increment 19 Deep-Dive)

### Backend: Kalcifer.AI

```
lib/kalcifer/ai/
├── chat_handler.ex        # GenServer per-session
├── system_prompt.ex       # Dynamic prompt builder
├── tool_executor.ex       # Tool call → Kalcifer API
├── tools/
│   ├── create_flow.ex     # "შემიქმენი flow"
│   ├── add_node.ex        # "დაამატე email node"
│   ├── modify_node.ex     # "შეცვალე wait 2 დღიდან 3-ზე"
│   ├── simulate_flow.ex   # "გატესტე dry run-ით"
│   ├── analyze_flow.ex    # "რა პრობლემა აქვს ამ flow-ს?"
│   ├── debug_instance.ex  # "რატომ ჩავარდა?"
│   └── query_analytics.ex # "რამდენმა გაიარა ეს flow?"
├── context_builder.ex     # Builds context for AI
└── streaming.ex           # SSE streaming to frontend
```

### System Prompt Strategy

```
კალციფერი ხარ — flow orchestration engine-ის AI ასისტენტი.
შენ არის სახლის გული. მომხმარებელი შენთან საუბრით აშენებს flow-ებს.

შენ იცი:
- 24 node type და მათი კონფიგურაცია
- Flow graph სტრუქტურა (nodes + edges)
- Execution lifecycle (trigger → nodes → complete/fail)
- Analytics: funnel, A/B, conversion data
- Customer segments და preferences

შენ შეგიძლია:
- create_flow: ახალი flow-ის შექმნა
- add_node: არსებულ flow-ში node-ის დამატება
- modify_node: node-ის კონფიგურაციის შეცვლა
- simulate_flow: dry run გაშვება
- analyze_flow: flow-ის ანალიზი და რეკომენდაციები
- debug_instance: ჩავარდნილი instance-ის დიაგნოსტიკა
- query_analytics: მონაცემების მოთხოვნა

ყოველთვის ქართულად უპასუხე თუ ქართულად გეკითხებიან.
```

### AI Tool Interface

```typescript
// Frontend: AI tool call triggers canvas update
interface AIToolCall {
  tool: 'create_flow' | 'add_node' | 'modify_node' | 'simulate_flow' | ...
  args: Record<string, unknown>
}

// Example: AI creates a flow
{
  tool: 'create_flow',
  args: {
    name: 'Welcome Email Sequence',
    description: '3-step onboarding flow',
    nodes: [
      { type: 'event_entry', config: { event_type: 'user_signup' } },
      { type: 'send_email', config: { template: 'welcome', subject: 'Welcome!' } },
      { type: 'wait', config: { duration: '2d' } },
      { type: 'send_email', config: { template: 'tips', subject: 'Getting Started' } },
      { type: 'end', config: {} }
    ],
    edges: 'auto'  // AI or backend auto-generates edges
  }
}
```

---

## Docker Development Setup

```yaml
# docker-compose.dev.yml — extended for frontend
services:
  postgres:
    # ... (existing)

  app:
    # ... (existing Elixir app)

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.dev
    volumes:
      - ./frontend:/app
      - node_modules:/app/node_modules
    ports:
      - "5173:5173"
    environment:
      VITE_API_URL: http://localhost:4500
      VITE_WS_URL: ws://localhost:4500
```

### ფოლდერ სტრუქტურა

```
kalcifer/
├── lib/                    # Elixir backend (existing)
├── test/                   # Elixir tests (existing)
├── frontend/               # React SPA (NEW)
│   ├── Dockerfile.dev
│   ├── package.json
│   ├── vite.config.ts
│   ├── tailwind.config.ts
│   ├── tsconfig.json
│   ├── index.html
│   ├── public/
│   │   └── favicon.svg     # Calcifer flame icon
│   └── src/
│       ├── main.tsx
│       ├── App.tsx
│       ├── router.tsx
│       ├── api/             # API client + hooks
│       ├── store/           # Zustand stores
│       ├── pages/           # Route pages
│       ├── components/      # Shared components
│       ├── theme/           # Theme system
│       ├── i18n/            # Translations
│       └── types/           # TypeScript types
├── ui-prototype/           # Static HTML reference (existing)
├── docs/                   # Documentation (existing)
└── docker-compose.dev.yml  # Updated
```

---

## თანმიმდევრობა და ვადები

```
Increment 18: Setup & Design System        ← დაწყება აქედან
Increment 19: AI Chat System (ბირთვი)      ← ყველაზე მნიშვნელოვანი
Increment 20: Flow Editor (Canvas)
Increment 21: Work Page (Orchestrator)
Increment 22: Engine Room (Monitoring)
Increment 23: Browse & Polish
```

### დამოკიდებულებები

```
18 (Setup)
 │
 ├── 19 (AI Chat) ─────┐
 │                      │
 ├── 20 (Flow Editor) ──┤── 21 (Work Page)
 │                      │
 └── 22 (Engine Room) ──┘── 23 (Browse + Polish)
```

- 19 და 20 ნაწილობრივ პარალელურად შეიძლება
- 21 მოითხოვს 19-ს (chat) და 20-ს (canvas)
- 22 დამოუკიდებელია 20/21-ისგან
- 23 ბოლო — ყველაფრის polish

---

## შემოწმების კრიტერიუმი

### Increment-ის დასრულება:
1. ✅ ყველა კომპონენტი render-დება სწორად
2. ✅ თემები მუშაობს (6 × 2 = 12 variations)
3. ✅ API-სთან კავშირი მუშაობს
4. ✅ TypeScript: 0 errors
5. ✅ Vitest: 0 failures
6. ✅ ESLint: 0 errors

### Phase 2 დასრულება:
- [ ] AI chat flow-ებს ქმნის ბუნებრივი ენით
- [ ] Flow editor drag-drop + simulation მუშაობს
- [ ] Real-time monitoring WebSocket-ით
- [ ] Provider simulators (email, SMS, webhook viewers)
- [ ] ქართული + ინგლისური ენები
- [ ] 12 თემა (6 palette × 2 mode)
- [ ] Docker-ში ყველაფერი ერთად ეშვება
