# Research: AI როგორც მარკეტინგის მრჩეველი

> **სტატუსი**: 🔬 საკვლევი
> **წყარო**: მომხმარებლის feedback — "კონსულტაციებს ვერ გამიწევ? ინსაითები მჭირდება ზოგად ცოდნაზეც და ჩვენი გამოცდილებაზეც"
> **პრიორიტეტი**: Increment 19-ის შემდეგ, სავარაუდოდ Increment 24+

---

## პრობლემა

Kalcifer-ის AI ამჟამად flow builder + debugger-ია. მაგრამ მომხმარებლის მოლოდინი უფრო ფართოა:

- "ხალხი მოგიყვანო, კონტენტი შევქმნა, სტრატეგია დავგეგმო — შენ ამ ყველაფრის კონსულტაციებს ვერ გამიწევ?"
- ინსაითები ზოგადი ცოდნიდან (ინდუსტრიის ბენჩმარკები, best practices, კვლევები)
- ინსაითები კონკრეტული გამოცდილებიდან (წარსული კამპანიები, A/B ტესტები, ტრენდები)

ეს არის პოზიციონირების საკითხი: AI არა მხოლოდ "flow აწყობს", არამედ მარკეტინგის მრჩეველია.

---

## მიმართულებები

### 1. Web Search / External Knowledge

**რა არის**: AI-ს შეუძლია ინტერნეტში მოძებნოს ინფორმაცია — ბენჩმარკები, სტატისტიკები, best practices.

**მაგალითი**: "რა არის საშუალო email open rate SaaS-ისთვის?" → AI ეძებს, პასუხობს წყაროებით.

**ტექნიკურად**:
- Anthropic API-ს აქვს web search tool (beta)
- ალტერნატივა: Tavily / Serper API ინტეგრაცია
- ახალი tool: `web_search` — query → results → AI summarizes

**სირთულე**: დაბალი. API ინტეგრაცია + ერთი tool.

---

### 2. RAG / Knowledge Base

**რა არის**: მომხმარებელი (ან ჩვენ) ატვირთავს დოკუმენტებს — სტატიები, PDF-ები, კვლევები, playbook-ები. AI ამას იყენებს პასუხებისთვის.

**მაგალითი**: ატვირთავ "Email Marketing Playbook 2026.pdf" → AI ციტირებს კონკრეტულ სტრატეგიებს.

**ტექნიკურად**:
- pgvector (PostgreSQL extension) — ვექტორული ძებნა, უკვე PostgreSQL 16 გვაქვს
- Document chunking pipeline (Elixir-ში ან Python sidecar)
- Embedding API (Anthropic / OpenAI embeddings)
- ახალი tools: `search_knowledge`, `upload_document`
- Schema: `knowledge_documents`, `knowledge_chunks` (with vector column)

**სირთულე**: საშუალო. pgvector setup + chunking pipeline + embedding.

---

### 3. Analytics-based Insights (ჩვენი მონაცემები)

**რა არის**: AI ხედავს კამპანიების/flow-ების ისტორიულ მონაცემებს და დასკვნებს აკეთებს.

**მაგალითი**: "ჩვენი ბოლო 5 კამპანია როგორ წავიდა?" → AI აანალიზებს conversion rates, drop-off points, timing patterns.

**ტექნიკურად**:
- ნაწილობრივ უკვე არსებობს: `analyze_flow`, `debug_instance` tools
- საჭირო: `query_analytics` tool — aggregated stats across flows/instances
- საჭირო: Analytics context (Increment 20-21-ში იგეგმება)
- `remember` tool-ით AI იმახსოვრებს ტრენდებს სესიებს შორის

**სირთულე**: საშუალო. Analytics infrastructure-ზეა დამოკიდებული.

---

### 4. Institutional Memory (Pattern Recognition)

**რა არის**: AI დროთა განმავლობაში სწავლობს ორგანიზაციის patterns-ს.

**მაგალითი**: "პარასკევს გაგზავნილი კამპანიები ყოველთვის უარესად მუშაობს" — AI ამას თავისით ამჩნევს და გაფრთხილებთ.

**ტექნიკურად**:
- `remember`/`recall` ბაზა უკვე არსებობს
- საჭირო: Proactive insight generation (scheduled job ან post-campaign analysis)
- ახალი tool: `suggest_improvements` — AI ავტომატურად გენერირებს რეკომენდაციებს
- Pattern storage: `operator_memories`-ის გაფართოება ან ახალი `insights` table

**სირთულე**: მაღალი. საჭიროა analytics data + pattern detection logic.

---

### 5. Proactive Notifications

**რა არის**: AI თავისით აგზავნის შეტყობინებებს/რეკომენდაციებს (Slack, in-app).

**მაგალითი**: "ბოლო 3 კამპანიაში email open rate 15%-ით დაეცა — გინდა გადავხედოთ?"

**ტექნიკურად**:
- `ai_notify` node უკვე არსებობს (PubSub)
- საჭირო: Scheduled analysis job (Oban) — პერიოდულად ამოწმებს მეტრიკებს
- საჭირო: Notification preferences (რა სიხშირით, რა არხით)
- Integration: Slack webhook, in-app notification center

**სირთულე**: მაღალი. Scheduled jobs + notification system + threshold logic.

---

## შემოთავაზებული პრიორიტეტი

```
Phase 1 (Increment 24): Web Search + Analytics Query
  └─ დაბალი სირთულე, მაღალი impact
  └─ web_search tool + query_analytics tool
  └─ მომხმარებელი მაშინვე ხედავს "კონსულტანტის" ღირებულებას

Phase 2 (Increment 25): RAG / Knowledge Base
  └─ pgvector + document upload + search_knowledge tool
  └─ ორგანიზაციის საკუთარი ცოდნის ბაზა

Phase 3 (Increment 26+): Institutional Memory + Proactive
  └─ Pattern detection + scheduled analysis + notifications
  └─ AI რომელიც თავისით ამჩნევს და გირჩევს
```

---

## კავშირი არსებულ არქიტექტურასთან

| არსებული | გაფართოება |
|----------|-----------|
| `Tools.execute/4` | ახალი tools: `web_search`, `query_analytics`, `search_knowledge` |
| `operator_memories` table | Insights storage, pattern tracking |
| `remember`/`recall` tools | Cross-session institutional knowledge |
| `ai_notify` node | Proactive notification delivery |
| `analyze_flow` tool | Aggregated multi-flow analysis |
| NodeRegistry (ETS) | Knowledge retrieval nodes (flow-ში RAG) |

---

## ღია კითხვები

1. RAG-ისთვის pgvector საკმარისია თუ dedicated vector DB (Qdrant, Pinecone) ჯობია?
2. Web search — Anthropic-ის built-in თუ third-party (Tavily) უფრო reliable?
3. Proactive insights — Oban scheduled job თუ real-time stream analysis?
4. Multi-tenant knowledge: თითოეულ tenant-ს საკუთარი knowledge base თუ shared + private?
5. Pricing: RAG / web search API calls → ახალი pricing tier?
