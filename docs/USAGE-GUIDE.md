# Kalcifer — გამოყენების გზამკვლევი

> **Version**: 0.1.0 — Phase 2 Complete
> **URL**: `http://localhost:5173` (frontend) / `http://localhost:4500` (API)

---

## სარჩევი

1. [დაწყება — გაშვება და ავტორიზაცია](#1-დაწყება)
2. [Work — ჩათი და ფლოუების მართვა](#2-work)
3. [Flow Editor — ვიზუალური რედაქტორი](#3-flow-editor)
4. [Engine Room — კონფიგურაცია და მონიტორინგი](#4-engine-room)
5. [Browse — ბიბლიოთეკა და ინსტანსები](#5-browse)
6. [API — ინტეგრაციის ენდფოინთები](#6-api)
7. [Node System — 29 ბირთვი ნაბიჯი](#7-node-system)
8. [AI ინტეგრაცია](#8-ai)

---

## 1. დაწყება

### გაშვება

```bash
# პირველად
mix setup                    # deps + DB create + migrate
cd frontend && npm install

# ყოველდღიური
docker compose -f docker-compose.dev.yml up -d   # postgres + app + frontend
# ან ცალ-ცალკე:
mix phx.server               # backend → localhost:4500
cd frontend && npm run dev   # frontend → localhost:5173
```

### ავტორიზაცია

**Google OAuth** (production):
1. `.env`-ში: `VITE_GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com`
2. გახსენი `localhost:5173` → Login Page → "Sign in with Google"
3. ავტომატურად იქმნება User + Tenant

**Dev რეჟიმი** (OAuth-ის გარეშე):
- `VITE_GOOGLE_CLIENT_ID` არ არის → აპი ეხსნება ავტორიზაციის გარეშე
- "Demo Tenant" ავტომატურად იქმნება

### API Key ავტორიზაცია

Bearer token production API-სთვის:
```
Authorization: Bearer kal_xxxxxxxxxxxxx
```
Engine Room → AI Config → API Key სექცია — ახალი key-ის გენერაცია.

---

## 2. Work — ჩათი და ფლოუების მართვა

**URL**: `localhost:5173/` (მთავარი გვერდი)

### 2.1 ლეიაუტი — 5 ეტაპი

| ეტაპი | აღწერა |
|-------|--------|
| **welcome** | პირველი ვიზიტი — მისასალმებელი ეკრანი |
| **lobby** | sidebar-ით, საუბარი არჩეული არ არის |
| **chat** | ჩათი აქტიურია |
| **split** | ჩათი (მარცხნივ) + კონტექსტი (მარჯვნივ) |
| **context** | კომპაქტური ჩათი + გაშლილი კონტექსტი |

### 2.2 ჩათი — AI ბირთვი

- ტექსტის დაწერა → Enter (Shift+Enter = ახალი ხაზი)
- AI ავტომატურად კლასიფიცირებს საუბარს: 📣 კამპანია, ⚡ ფლოუ, 📊 ანალიზი, 🔍 დიაგნოსტიკა
- Tool activity badges: ხედავ რას აკეთებს AI (ფლოუს შექმნა, ანალიზი, გრაფის წაკითხვა...)

### 2.3 კონტექსტის პანელი

**ავტომატურად იხსნება** როცა:
- საუბარი კლასიფიცირდება როგორც "flow" კონკრეტული flow_id-ით
- AI-ის tool-ი (create_flow, get_flow) აბრუნებს ფლოუს

**შეიცავს**:
- **Flow Editor (inline)** — სრული ინტერაქტიული რედაქტორი ჩათის გვერდით
- ⤢/⤡ — გადიდება/შემცირება
- ✕ — დახურვა

### 2.4 Sidebar

- საუბრები დაჯგუფებულია ტიპით (კამპანიები, ფლოუები, ანალიზი, დიაგნოსტიკა)
- Right-click → სახელის შეცვლა, არქივში გადატანა, წაშლა
- Double-click → სახელის რედაქტირება
- "+ ახალი სესია" ღილაკი

---

## 3. Flow Editor — ვიზუალური რედაქტორი

### 3.1 გახსნის გზები

1. **Work Page-დან** — ჩათში ფლოუზე საუბრისას ავტომატურად
2. **სრულ ედიტორში** — `/editor?flow=<flow_id>`
3. **Browse Page-დან** — ფლოუს კარტაზე კლიკი

### 3.2 რეჟიმები

| რეჟიმი | აღწერა |
|--------|--------|
| **✎ Edit** | ნაბიჯების დამატება, კავშირები, კონფიგურაცია |
| **▶ Simulate** | Dry Run — ნაბიჯ-ნაბიჯ სიმულაცია ანიმაციით |
| **◉ Live** | რეალურ დროში — WebSocket-ით აქტიური ინსტანსების თვალყურის დევნება |

### 3.3 რედაქტირების ინსტრუმენტები

| მოქმედება | როგორ |
|----------|-------|
| ნაბიჯის დამატება | + ღილაკი → Node Palette |
| ნაბიჯის კონფიგურაცია | კლიკი ნაბიჯზე → Config Panel |
| ნაბიჯის წაშლა | Delete / Backspace |
| კავშირის შექმნა | handle-დან handle-ზე drag |
| Undo / Redo | Ctrl+Z / Ctrl+Y |
| Copy / Paste | Ctrl+C / Ctrl+V (არჩეული ნაბიჯები) |
| შენახვა | 💾 ან Ctrl+S |
| ვალიდაცია | ✓ ღილაკი → ⚠ warnings badges |
| AI Suggestions | ვალიდაციის შემდეგ → 💡 status bar-ში |
| ანალიტიკა | 📊 toggle → node-ებზე execution stats |
| ექსპორტი | ↓ ღილაკი → JSON ფაილის ჩამოტვირთვა |

### 3.4 Node Config Panel — ტიპ-სპეციფიკური ფორმები

**Condition node**:
- Field: კონტექსტის ველი (მაგ: `age`, `plan`)
- Operator: =, ≠, >, <, შეიცავს, არსებობს, სიაში, regex...
- Value: შედარების მნიშვნელობა

**Send Email node**:
- Subject: `გამარჯობა {{name}}!` — ცვლადების ინტერპოლაცია
- Body: HTML/ტექსტი {{variable}} სინტაქსით
- From Name, Reply-To, Template ID

**Send SMS node**:
- Body: ტექსტი + 160 სიმბოლოს მთვლელი
- Sender ID
- **ტელეფონის მოკაპი** — real-time preview

**Wait node**: Duration (1d, 2h, 30m)
**Webhook node**: URL + Method
**A/B Split**: Split ratio %

### 3.5 სიმულაცია (Dry Run)

1. ▶ Simulate რეჟიმში გადასვლა
2. ▶ Dry Run ღილაკი
3. ნაბიჯები ერთმანეთის მიყოლებით ანთებულობენ (ყვითელი = აქტიური, მწვანე = დასრულებული)
4. ✓/✗ badges ნაბიჯებზე
5. Reset / Re-run

### 3.6 Live Mode

1. ◉ Live რეჟიმში გადასვლა
2. WebSocket ავტომატურად უკავშირდება
3. აქტიური ინსტანსები ჩანს status bar-ში
4. ნაბიჯები real-time-ში ინთება
5. **Instance picker** — 📋 ღილაკი → კონკრეტული ინსტანსის არჩევა → timeline overlay

### 3.7 ანალიტიკა (Node-Level)

📊 ღილაკზე დაჭერით ყოველ ნაბიჯზე ჩანს:
- ✓ შესრულებული რაოდენობა
- ✗ წარუმატებელი (თუ არის)
- საშუალო დრო (ms/s/m)
- წარმატების % (success rate)

---

## 4. Engine Room — კონფიგურაცია და მონიტორინგი

**URL**: `localhost:5173/engine`

### 4.1 AI Config

- **მოდელის არჩევა**: Claude Haiku/Sonnet, GPT-4o/Mini, Gemini Pro/Flash
- **Provider Keys**: პროვაიდერ-სპეციფიკური API key-ების მართვა
- **საუბრების სტატისტიკა**: საუბრები, შეტყობინებები, ფლოუები, მეხსიერება

### 4.2 📡 Channels — არხების კონფიგურაცია

| არხი | ხელმისაწვდომი პროვაიდერები |
|------|--------------------------|
| 📧 email | log, sendgrid, ses, mailgun, postmark |
| 💬 sms | log, twilio, vonage, messagebird |
| 🔔 push | log, firebase, onesignal, expo |
| 💚 whatsapp | log, twilio, messagebird |
| 🔗 webhook | log, webhook |

- `log` = სატესტო რეჟიმი (კონსოლში წერს)
- Dropdown-ით პროვაიდერის არჩევა → ავტომატურად ინახება

### 4.3 🔑 API Key

- ამჟამინდელი key-ს ჰეში ინახება (არ ჩანს)
- "🔄 ახალი Key-ის გენერაცია" → ახალი `kal_*` key → **ერთხელ ჩანს, დააკოპირე!**
- ძველი key ავტომატურად ბათილდება

### 4.4 Node Registry

- 29 რეგისტრირებული ნაბიჯის ტიპი
- კატეგორიებად: trigger, condition, wait, action, end

### 4.5 Oban Queues

- flow_triggers: 10 workers
- delayed_resume: 20 workers
- maintenance: 5 workers
- რაოდენობა და სტატუსი

### 4.6 System Health

- BEAM VM: memory, processes
- DB latency
- HealthCheck endpoint

---

## 5. Browse — ბიბლიოთეკა და ინსტანსები

**URL**: `localhost:5173/browse`

### 5.1 ფლოუების ბიბლიოთეკა

- ყველა ფლოუს ჩამონათვალი: სახელი, სტატუსი, თარიღი
- სტატუსი: Draft → Active ↔ Paused → Archived
- კლიკი → ედიტორში გახსნა

### 5.2 ინსტანსების პანელი

- ფლოუს არჩევა → მისი ინსტანსების ჩამონათვალი
- სტატუსი: running, completed, failed, waiting
- Timeline viewer: ნაბიჯ-ნაბიჯ execution path, duration, output JSON

---

## 6. API — ინტეგრაციის ენდფოინთები

### 6.1 ავტორიზაცია

```
POST /api/v1/auth/google        # Google OAuth login
GET  /api/v1/auth/me            # მიმდინარე მომხმარებელი
```

### 6.2 ფლოუები (Authenticated: Bearer token)

```
GET    /api/v1/flows              # ჩამონათვალი
POST   /api/v1/flows              # შექმნა
GET    /api/v1/flows/:id          # დეტალები
PUT    /api/v1/flows/:id          # განახლება
DELETE /api/v1/flows/:id          # წაშლა
POST   /api/v1/flows/:id/activate # აქტივაცია
POST   /api/v1/flows/:id/pause    # დაპაუზება
GET    /api/v1/flows/:id/export   # ექსპორტი (JSON)
POST   /api/v1/flows/import       # იმპორტი (JSON)
```

### 6.3 ვერსიები

```
GET /api/v1/flows/:flow_id/versions              # ვერსიების ჩამონათვალი
PUT /api/v1/flows/:flow_id/versions/:number       # გრაფის შენახვა
```

### 6.4 ინსტანსები და Triggers

```
POST /api/v1/flows/:flow_id/trigger                # ინსტანსის გაშვება
POST /api/v1/events                                # ივენთის გაგზავნა
GET  /api/v1/flows/:flow_id/instances              # ინსტანსების ჩამონათვალი
GET  /api/v1/instances/:id/timeline                # Timeline
```

### 6.5 ანალიტიკა

```
GET /api/v1/flows/:flow_id/analytics/summary       # ზოგადი სტატისტიკა
GET /api/v1/flows/:flow_id/analytics/nodes          # ნაბიჯ-ნაბიჯ სტატისტიკა + avg_duration_ms
GET /api/v1/flows/:flow_id/analytics/funnel         # Funnel ანალიზი
```

### 6.6 Deliveries

```
GET  /api/v1/deliveries                            # მიწოდებების ჩამონათვალი
GET  /api/v1/deliveries/stats                      # სტატისტიკა (pending/sent/delivered/bounced/failed)
POST /api/v1/deliveries/:id/status                 # სტატუსის განახლება (webhook callback)
```

### 6.7 ჩათი

```
POST /api/v1/chat                                  # SSE streaming chat
```

### 6.8 Audit Log

```
GET /api/v1/audit                                  # აუდიტი (?resource_type=flow&limit=50)
```

### 6.9 Settings

```
GET  /api/v1/settings                              # AI config + channel providers
PUT  /api/v1/settings                              # განახლება
POST /api/v1/settings/regenerate-api-key           # ახალი API key
```

### 6.10 Rate Limiting

- Authenticated pipeline: 500 req/min default
- Headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`
- 429 Too Many Requests + `Retry-After` header

---

## 7. Node System — 29 ბირთვი ნაბიჯი

### 7.1 Triggers (შესასვლელები)

| ტიპი | აღწერა |
|------|--------|
| `event_entry` | ივენთ-ბაზირებული entry (user_signup, purchase...) |
| `segment_entry` | სეგმენტის წევრობით entry |
| `webhook_entry` | HTTP webhook-ით entry |

### 7.2 Conditions (პირობები)

| ტიპი | აღწერა |
|------|--------|
| `condition` | ზოგადი პირობა: 10 ოპერატორი (=, ≠, >, <, contains, exists, in, regex...) |
| `ab_split` | A/B ტესტი: პროცენტული გაყოფა |
| `check_segment` | სეგმენტის შემოწმება |
| `frequency_cap` | სიხშირის ლიმიტი |
| `preference_gate` | Opt-in/opt-out შემოწმება |
| `ai_decide` | AI-ბაზირებული გადაწყვეტილება |
| `flow_router` | AI-ბაზირებული ფლოუს მარშრუტიზაცია |

### 7.3 Waits (ლოდინი)

| ტიპი | აღწერა |
|------|--------|
| `wait` | ფიქსირებული ლოდინი (3d, 2h, 30m) |
| `wait_until` | კონკრეტული თარიღამდე ლოდინი |
| `wait_for_event` | ივენთის მოლოდინი timeout-ით |

### 7.4 Actions (მოქმედებები)

| ტიპი | აღწერა |
|------|--------|
| `send_email` | ემაილი (subject/body {{interpolation}}, from, reply-to) |
| `send_sms` | SMS (body, sender_id, char counter) |
| `send_push` | Push notification |
| `send_whatsapp` | WhatsApp შეტყობინება |
| `send_in_app` | In-app notification |
| `call_webhook` | HTTP webhook call |
| `update_profile` | მომხმარებლის პროფილის განახლება |
| `add_tag` | ტეგის დამატება |
| `custom_code` | Elixir კოდის შესრულება |
| `track_conversion` | კონვერსიის ჩაწერა |
| `ai_think` | AI ფიქრი — LLM call (per-node model override) |
| `ai_notify` | ოპერატორის შეტყობინება |
| `agent` | მრავალ-ნაბიჯიანი AI აგენტი (chat_with_tools) |
| `parallel_group` | პარალელური ამოცანების შესრულება (Task.async_stream) |
| `sub_flow` | ქვე-ფლოუს გაშვება (child FlowInstance) |
| `memory_recall` | ოპერატორის მეხსიერების წაკითხვა |

### 7.5 Ends (დასასრულები)

| ტიპი | აღწერა |
|------|--------|
| `exit` | ფლოუს დასრულება |
| `goal_reached` | მიზნის მიღწევა (conversion tracking) |

---

## 8. AI ინტეგრაცია

### 8.1 ჩათის ბრძანებები (ბუნებრივი ენით)

| რა ვთხოვთ | რა ხდება |
|-----------|---------|
| "შემიქმენი welcome email flow" | AI ქმნის ფლოუს სრული გრაფით |
| "condition-ში ასაკი 18-ზე მეტი გამოიყენე" | AI ცვლის node-ის config-ს |
| "ეს wait ნაბიჯი წაშალე" | AI შლის ნაბიჯს + კავშირებს |
| "რა პრობლემა აქვს ამ ფლოუს?" | AI ანალიზი + suggestions |
| "ეს ინსტანსი რატომ ჩავარდა?" | AI ხედავს execution steps-ს |

### 8.2 AI Tools

| Tool | აღწერა |
|------|--------|
| `classify_session` | საუბრის კლასიფიკაცია + flow_id |
| `list_flows` | ფლოუების ჩამონათვალი |
| `get_flow` / `get_flow_graph` | ფლოუს დეტალები |
| `create_flow` | ფლოუს შექმნა (სრული გრაფით) |
| `add_node` / `modify_node` / `remove_node` | ნაბიჯების მართვა |
| `analyze_flow` | ფლოუს ანალიზი + suggestions |
| `debug_instance` | ინსტანსის დიაგნოსტიკა |
| `remember` / `recall` | მეხსიერება |

### 8.3 მრავალ-მოდელის მხარდაჭერა

AI node-ებს (`ai_think`, `ai_decide`, `agent`, `flow_router`) config-ში `model` field:
```json
{
  "prompt": "გაანალიზე მომხმარებელი",
  "model": "gpt-4o"
}
```

Council flow-ში სხვადასხვა პერსონას სხვადასხვა მოდელი:
- 🌙 ოცნებისმყრელი → claude-sonnet
- 🏗 რეალისტი → gpt-4o
- 🔍 სკეპტიკოსი → claude-haiku

### 8.4 Cognitive Architecture — Council Flow

7-ნაბიჯიანი deliberation:
1. entry → 2. dreamer (ოცნებისმყრელი) → 3. realist (რეალისტი) → 4. skeptic (სკეპტიკოსი) → 5. synthesizer (სინთეზატორი) → 6. executor (აგენტი) → 7. exit

გააქტიურება: "საბჭო", "council", "დაფიქრდი" — keywords ჩათში.

---

## Docker Dev Setup

```yaml
# docker-compose.dev.yml
services:
  postgres:  # port 5432
  app:       # port 4500 (Elixir + Phoenix)
  frontend:  # port 5173 (React + Vite)
```

Backend ცვლილებების შემდეგ:
```bash
docker compose -f docker-compose.dev.yml restart app
```

---

## პროექტის სტრუქტურა (მოკლედ)

```
lib/kalcifer/
  flows/          # Flow, FlowVersion, FlowInstance, FlowGraph, ExecutionStep
  engine/         # FlowServer, NodeExecutor, NodeRegistry (29 nodes)
  channels/       # Delivery, ChannelSender, Providers (log, webhook)
  analytics/      # FlowStats, NodeStats, Collector
  ai/             # Client (Anthropic/OpenAI/Google), Tools, Context, Memory
  accounts/       # User (Google OAuth)
  audit/          # Entry (audit log)
  tenants/        # Tenant, settings, API key hashing
  marketing/      # Journey (marketing wrapper)

lib/kalcifer_web/
  controllers/    # 12 controllers
  plugs/          # ApiKeyAuth, UserAuth, RateLimiter
  channels/       # FlowChannel (WebSocket)

frontend/src/
  pages/          # WorkPage, EnginePage, BrowsePage, LoginPage, FlowEditorPage
  components/     # ChatPanel, FlowCanvas, FlowEditorInline, Sidebar, TopBar...
  lib/            # api.ts, chat.ts, themes.ts, useFlowSocket.ts
```
