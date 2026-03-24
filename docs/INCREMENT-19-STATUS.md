# Increment 19: AI Chat System — სტატუსი და გეგმა

> **სტატუსი**: 🔨 მიმდინარე
> **მიზანი**: AI chat infrastructure — streaming, tool calls, conversation persistence, memory

---

## რა არის გაკეთებული ✅

### 19a: Backend — AI Infrastructure
- [x] `Kalcifer.AI.Client` — Claude API კლიენტი (Finch streaming)
- [x] `chat_with_tools/5` — tool use loop (non-streaming rounds → streaming final)
- [x] SSE streaming endpoint `POST /api/v1/chat`
- [x] System prompt ქართული პიროვნებით (კალციფერის ხასიათი)
- [x] `Kalcifer.AI.Tools` — 12 tools (flow CRUD, graph manipulation, analysis, debug, memory)
- [x] `Kalcifer.AI.Context` — Conversation + Memory CRUD
- [x] DB migration — conversations, conversation_messages, operator_memories tables
- [x] Schema-ები: Conversation, ConversationMessage, Memory

### 19a+: AI Nodes (ბონუსი — PHASE-2 გეგმაში არ იყო)
- [x] `ai_think` — AI text generation node (flow context-ით)
- [x] `ai_decide` — AI branching node (condition via Claude)
- [x] `ai_notify` — Operator notification node (PubSub)
- [x] NodeRegistry-ში რეგისტრირებული (25 node type)
- [x] FlowGraph-ში ai_decide branching support

### 19b: Frontend — ChatPanel
- [x] SSE streaming display (delta events)
- [x] Markdown rendering (react-markdown)
- [x] Tool activity badges (animated, Georgian labels for 12 tools)
- [x] User/AI message styling (alignment, colors, avatars)
- [x] Typing indicator

---

## ნაბიჯები

### ნაბიჯი 1: Conversation Persistence (backend) ✅
- [x] ChatController: conversation_id support, create/load history
- [x] SSE `init` event → conversation_id frontend-ს
- [x] User + assistant messages DB-ში
- [x] Memory auto-load system prompt-ში
- [x] 5 ChatController tests passing

### ნაბიჯი 2: Session Classification + Conversation API ✅
- [x] Conversation schema: kind, entity_type, entity_id
- [x] classify_session AI tool (campaign/flow/analysis/debug)
- [x] classify_changeset — ერთხელ კლასიფიცირებული ვეღარ იცვლება
- [x] link_entity — სესია ↔ Journey/Flow კავშირი
- [x] GET /conversations (kind filter, status=all), GET /conversations/:id, POST archive
- [x] PUT /conversations/:id (rename), DELETE /conversations/:id (unclassified only)
- [x] ConversationController + 12 tests
- [x] Frontend: session_classified SSE event, kind badge header-ში
- [x] System prompt: classify_session ინსტრუქცია
- [x] Migration: add_kind_to_conversations

### ნაბიჯი 3: Frontend — Conversation History ✅
- [x] 3-stage system: welcome → lobby → chat
- [x] WelcomeScreen: breathing avatar, hint buttons, exit animations
- [x] Sidebar: grouped conversations (unclassified → by kind → archived)
- [x] Right-click context menu (rename, archive, delete)
- [x] Double-click inline rename
- [x] Delete vs archive rules (unclassified → delete, classified → archive)
- [x] URL state sync (`?c=conversationId`)
- [x] Backend: rename + delete endpoints with business rules
- [x] loadHistory race condition fix (stream overwrite prevention)
- [x] "ახალი საუბარი" button removed from chat (sidebar handles it)

**ფაილები**: `WorkPage.tsx`, `Sidebar.tsx`, `WelcomeScreen.tsx`, `ChatPanel.tsx`, `api.ts`, `index.css`

### ნაბიჯი 4: დამატებითი Tools (19c/19d) ✅
- [x] `get_flow_graph` — flow version-ის graph (nodes + edges)
- [x] `add_node` — node + edges დამატება draft version-ში
- [x] `modify_node` — node config-ის განახლება
- [x] `analyze_flow` — preflight, categories, entry/end nodes, context deps
- [x] `debug_instance` — instance status, execution steps, errors
- [x] Draft version management: `get_or_create_draft_version/1`
- [x] 15 new tool tests (31 total in tools_test.exs)

**ფაილები**: `tools.ex`, `step_store.ex`, `tools_test.exs`

**შენიშვნა**: `simulate` tool Increment 20-ში გადავიდა (Flow Editor + dry run UI)

### ნაბიჯი 5: AI Nodes Tests ✅
```
5.1  ai_think tests — 11 tests (mock API, context, dry run, validation) ✅
5.2  ai_decide tests — 12 tests (branch selection, fallback, case-insensitive) ✅
5.3  ai_notify tests — 10 tests (PubSub, interpolation, summarize, defaults) ✅
5.4  ai_agent tests — 14 tests (tool tracking, PubSub broadcasts, context) ✅
5.5  helpers tests — 10 tests (interpolate, summarize_context, build_messages) ✅
```

**ფაილები**: `test/kalcifer/engine/nodes/action/ai/` (57 tests total)

### ნაბიჯი 5.5: Test Suite Health Fix ✅
```
5.5.1  TenantResolver extraction — shared auth header + Demo Tenant fallback ✅
5.5.2  Route shadowing fix — unauthenticated/authenticated scope conflicts ✅
5.5.3  25 test failures fixed across controllers and tools ✅
```

### ნაბიჯი 6: End-to-End Verification ← შემდეგი
```
6.1  Docker-ში ყველაფრის გაშვება ✅
6.2  ჩათში tool use flow-ის ცდა (create_flow, add_node, remember/recall)
6.3  classify_session-ის ვერიფიკაცია (badge ჩნდება header-ში?)
6.4  Conversation persistence (refresh → history remains, URL sync)
6.5  Memory persistence (new conversation → recalls old memories)
6.6  Sidebar: rename, archive, delete, grouping
```

---

## ტესტების სტატუსი

| მოდული | ტესტები | სტატუსი |
|--------|---------|---------|
| Context (conversations, memory) | 22 | ✅ passing |
| Tools (12 tools + classify) | 31 | ✅ passing |
| ChatController (SSE, persistence) | 5 | ✅ passing |
| ConversationController (API) | 12 | ✅ passing |
| Client (API key check) | 1 | ✅ passing (Mox) |
| AI Nodes (think, decide, notify, agent, helpers) | 57 | ✅ passing |
| Frontend (Vitest) | 26 | ✅ passing |
| **სულ backend** | **780** | ✅ **0 failures** |

---

## პრიორიტეტი

```
ნაბიჯი 1 (Persistence)         ✅ დასრულდა
ნაბიჯი 2 (Classification + API) ✅ დასრულდა
ნაბიჯი 3 (Frontend History)     ✅ დასრულდა
ნაბიჯი 4 (More Tools)           ✅ დასრულდა
ნაბიჯი 5 (AI Node Tests)        ✅ დასრულდა (57 tests)
ნაბიჯი 5.5 (Test Suite Fix)     ✅ დასრულდა (780 tests, 0 failures)
    ↓
ნაბიჯი 6 (E2E)                 ← შემდეგი
```
