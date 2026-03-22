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
- [x] `Kalcifer.AI.Tools` — 6 tool (list/get/create_flow, list_node_types, remember, recall)
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
- [x] Tool activity badges (animated, Georgian labels)
- [x] User/AI message styling (alignment, colors, avatars)
- [x] Typing indicator

---

## რა არის დარჩენილი ❌

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
- [x] GET /conversations (kind filter), GET /conversations/:id, POST archive
- [x] ConversationController + 5 tests
- [x] Frontend: session_classified SSE event, kind badge header-ში
- [x] System prompt: classify_session ინსტრუქცია
- [x] Migration: add_kind_to_conversations

### ნაბიჯი 3: Frontend — Conversation History
```
3.1  Sidebar-ში საუბრების სია (API-დან, kind-ით გაფილტრული)
3.2  საუბრის არჩევა → მესიჯების ჩატვირთვა
3.3  Kind icons + labels sidebar-ში
```

**ფაილები**: `ChatPanel.tsx`, `api.ts`, ახალი `ConversationList.tsx`

### ნაბიჯი 4: AI Module Tests
```
4.1  Context tests — conversation CRUD, message add, memory upsert/recall/forget
4.2  Tools tests — ყველა 6 tool-ის execute (Mox-ით ან real DB)
4.3  AI nodes tests — think (mock Claude), decide (branch selection), notify (PubSub)
4.4  ChatController integration — SSE streaming, tool flow, error handling
```

**ფაილები**: `test/kalcifer/ai/` ფოლდერი

### ნაბიჯი 5: დამატებითი Tools (19c/19d გეგმიდან)
```
5.1  add_node tool — არსებულ flow-ში node-ის დამატება
5.2  modify_node tool — node config-ის შეცვლა
5.3  simulate tool — dry run გაშვება
5.4  analyze_flow tool — flow structure analysis
5.5  debug_instance tool — execution step diagnosis
```

**ფაილები**: `tools.ex`-ში ახალი definitions + executors

### ნაბიჯი 6: End-to-End Verification
```
6.1  Docker-ში ყველაფრის გაშვება
6.2  ჩათში tool use flow-ის ცდა (create_flow, remember/recall)
6.3  Conversation persistence-ის ვერიფიკაცია (refresh → history remains)
6.4  Memory persistence-ის ვერიფიკაცია (new conversation → recalls old memories)
```

---

## პრიორიტეტი

```
ნაბიჯი 1 (Persistence) ← ყველაზე მნიშვნელოვანი, ამის გარეშე AI-ს მეხსიერება არ აქვს
    ↓
ნაბიჯი 4 (Tests) ← ტესტები პარალელურად ან მაშინვე მერე
    ↓
ნაბიჯი 2 (Conv API) ← frontend-ისთვის
    ↓
ნაბიჯი 3 (Frontend History) ← UX
    ↓
ნაბიჯი 5 (More Tools) ← ფუნქციონალობა
    ↓
ნაბიჯი 6 (E2E) ← ვერიფიკაცია
```
