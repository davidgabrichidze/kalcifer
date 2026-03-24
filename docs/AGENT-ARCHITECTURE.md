# Kalcifer Cognitive Agent Architecture — Design Document

## ფილოსოფია

**LLM = ტვინი.** აზროვნება, გადაწყვეტილება, კრეატივი.

**Flow Engine = ნერვული სისტემა.** ტვინების ორკესტრაცია, კომუნიკაცია, recovery, persistence, visibility.

ერთი LLM call ("ჩატი + tools") არ არის აგენტიკურობა. აგენტიკურობა არის:
- რამდენიმე "ტვინის" კოორდინირებული მუშაობა
- ყოველ "ტვინს" თავისი როლი, სისტემური პრომპტი, tools
- checkpoint/recovery — თუ ერთი "ტვინი" crash-დება, სისტემა აგრძელებს
- persistence — ყოველი ნაბიჯი DB-ში, audit trail
- visibility — მომხმარებელი ხედავს ვინ რას ფიქრობს

---

## ანალოგია: ტვინის სტრუქტურა → Flow Graph

```
ტვინის კომპონენტი          │  Flow Node ექვივალენტი
────────────────────────────┼──────────────────────────────
ამიგდალა (საფრთხე/ემოცია)  │  risk_assessor node
ნეოკორტექსი (ლოგიკა)       │  reasoner node
პრეფრონტალური (დაგეგმვა)   │  planner node
ჰიპოკამპი (მეხსიერება)     │  memory_retriever node
ბროკას არე (კომუნიკაცია)   │  responder node
ბაზალური განგლიები (ჩვევა)  │  pattern_matcher node
ოცნების ქარხანა            │  dreamer node (creative)
სკეპტიკოსი                 │  skeptic node (critical review)
```

ყოველი node = **პერსონა**:
- საკუთარი `system` prompt (როლი, პიროვნება, ფოკუსი)
- საკუთარი `model` (haiku სწრაფი ტრიაჟისთვის, opus ღრმა ანალიზისთვის)
- საკუთარი `tools` (ერთს code access, მეორეს web search, მესამეს DB queries)
- `context["accumulated"]`-ით იღებს წინა პერსონების output-ს

---

## არსებული primitives რომლებზეც ვაშენებთ

### უკვე გვაქვს engine-ში:
| Primitive | რას აკეთებს | როგორ ვიყენებთ |
|-----------|-------------|----------------|
| `ai_think` | ერთი LLM call + context | **საბაზისო persona node** — system prompt-ს უმატებს როლს |
| `ai_decide` | LLM-ით branching | **routing** — სკეპტიკოსმა serious concern-ები ნახა? → back to dreamer |
| `ai_notify` | PubSub broadcast | **visibility** — მომხმარებელს ატყობინებს რა ხდება |
| `context.accumulated` | node output sharing | **ტვინებს შორის კომუნიკაცია** |
| `FlowServer` | GenServer per instance | **ორკესტრაცია** — ყოველი agent session = FlowInstance |
| `ExecutionStep` | step persistence | **audit trail** — ყოველი "ფიქრი" DB-ში |
| `recovery` | crash recovery | **გამძლეობა** — crash-ის შემდეგ checkpoint-დან |
| `dry_run` | simulation | **ტესტირება** — agent flow-ს mock-ით გაშვება |

### რა აკლია:
| Gap | რას ნიშნავს |
|-----|-------------|
| **agentic node** | node რომელიც `chat_with_tools`-ს იძახებს (multi-round, tools) |
| **parallel execution** | რამდენიმე "ტვინი" ერთდროულად (Task.async_stream) |
| **sub-flow** | node რომელიც სხვა FlowInstance-ს უშვებს და ელოდება |
| **real-time SSE** | FlowServer → ChatController SSE bridge |
| **dynamic graph** | runtime-ში graph-ის მოდიფიკაცია (ლუპი, conditional paths) |

---

## ახალი Node ტიპები

### 1. `agent` — Agentic Persona Node

ai_think-ის გაფართოება: ერთი LLM call-ის ნაცვლად, multi-round tool loop.

```
config:
  system: "შენ ხარ ანალიტიკოსი. შენი სამუშაოა..."   # persona
  prompt: "გააანალიზე ეს flow და იპოვე პრობლემები"    # task
  model: "claude-haiku-4-5-20251001"                    # model choice
  tools: ["analyze_flow", "list_flows", "get_flow"]     # available tools (subset)
  max_rounds: 10                                        # tool round limit

category: :action
execute(config, context) →
  chat_with_tools(messages, filtered_tools, executor, callback, opts)
  {:completed, %{response, tool_calls_made, rounds}}
```

**ai_think-სგან განსხვავება:** ai_think = ერთი პასუხი. agent = მრავალნაბიჯიანი, tools-ით, iterative.

### 2. `sub_flow` — Sub-Flow Invocation Node

სხვა flow-ს უშვებს "ჩადგმულად" (child FlowInstance).

```
config:
  flow_id: "uuid-of-council-flow"
  version: "latest"
  input_mapping: {"topic" => "accumulated.planner.plan"}  # context → child initial_context

category: :action
execute(config, context) →
  FlowServer.start_link(child_args)
  # ელოდება child completion-ს
  {:completed, %{child_instance_id, child_result}}

  # ან async:
  {:waiting, %{type: "sub_flow", child_instance_id: id}}
  # resume-ს child completion trigger-ით
```

**use case:** "ტექ საბჭოს" flow-ს უშვებს node-ად, რომლის output შემდეგ მთავარ flow-ში ბრუნდება.

### 3. `parallel_group` — Parallel Execution Node

რამდენიმე "ტვინს" ერთდროულად უშვებს.

```
config:
  nodes: [
    {id: "risk", type: "agent", config: {system: "risk assessor..."}},
    {id: "creative", type: "agent", config: {system: "creative thinker..."}},
    {id: "practical", type: "agent", config: {system: "practical advisor..."}}
  ]
  strategy: "all" | "race" | "majority"  # wait for all, first, or majority

category: :action
execute(config, context) →
  Task.async_stream(nodes, &execute_child/1)
  {:completed, %{
    results: %{"risk" => ..., "creative" => ..., "practical" => ...}
  }}
```

**use case:** Dreamer, Realist, Skeptic ერთდროულად (სადაც თანმიმდევრული არ არის სავალდებულო).

### 4. `synthesizer` — Output Combination Node

რამდენიმე "ტვინის" output-ს აერთიანებს ერთ დასკვნაში.

```
config:
  system: "შენ ხარ სინთეზატორი. შეაჯამე სხვადასხვა პერსპექტივები..."
  input_nodes: ["risk", "creative", "practical"]  # which accumulated results to use
  format: "decision" | "summary" | "action_plan"

category: :action
execute(config, context) →
  # Reads context.accumulated for specified nodes
  # Calls LLM to synthesize
  {:completed, %{synthesis: "...", decision: "..."}}
```

---

## მაგალითი: "ტექ-საბჭო" როგორც Agent Flow

```
                    ┌─── [dreamer] ───┐
[intake] → [memory] ┤                 ├→ [synthesizer] → [respond]
                    │─── [realist] ───│
                    └─── [skeptic] ───┘

 ან თანმიმდევრული:

[intake] → [memory] → [dreamer] → [realist] → [skeptic] → [synthesizer] → [ai_decide: consensus?]
                                                                               ├─ yes → [respond]
                                                                               └─ no → [dreamer] ← (loop)
```

**Node configs:**

```json
{
  "nodes": [
    {
      "id": "intake",
      "type": "agent",
      "config": {
        "system": "შენ ხარ ტრიაჟის სპეციალისტი. გაარკვიე რა ტიპის ტექნიკური საკითხია.",
        "model": "claude-haiku-4-5-20251001",
        "tools": [],
        "prompt": "{{user_message}}"
      }
    },
    {
      "id": "memory",
      "type": "ai_think",
      "config": {
        "system": "მოძებნე რელევანტური გამოცდილება და კონტექსტი.",
        "prompt": "შეამოწმე წინა გადაწყვეტილებები ამ თემაზე."
      }
    },
    {
      "id": "dreamer",
      "type": "agent",
      "config": {
        "system": "შენ ხარ ოპტიმისტი ინოვატორი. იფიქრე ამბიციურად, შეზღუდვების გარეშე. შენი მიზანია ახალი შესაძლებლობების პოვნა.",
        "model": "claude-sonnet-4-5-20241022",
        "tools": ["analyze_flow", "list_node_types"],
        "prompt": "შემოგთავაზე ინოვაციური მიდგომა: {{accumulated.intake.response}}"
      }
    },
    {
      "id": "realist",
      "type": "agent",
      "config": {
        "system": "შენ ხარ პრაგმატისტი ინჟინერი. შეაფასე განხორციელებადობა, დროის ფრეიმი, რესურსები.",
        "tools": ["analyze_flow", "get_flow_graph"],
        "prompt": "შეაფასე ეს წინადადება: {{accumulated.dreamer.response}}"
      }
    },
    {
      "id": "skeptic",
      "type": "agent",
      "config": {
        "system": "შენ ხარ კრიტიკოსი. იპოვე სისუსტეები, რისკები, edge cases. შენი მიზანია სისტემის გამძლეობა.",
        "prompt": "გააკრიტიკე: {{accumulated.realist.response}}"
      }
    },
    {
      "id": "synthesizer",
      "type": "synthesizer",
      "config": {
        "system": "შეაჯამე სამი პერსპექტივა ერთ აქშენ-პლანად.",
        "input_nodes": ["dreamer", "realist", "skeptic"],
        "format": "action_plan"
      }
    },
    {
      "id": "respond",
      "type": "ai_notify",
      "config": {
        "channel": "chat",
        "summarize": true
      }
    }
  ],
  "edges": [
    {"source": "intake", "target": "memory"},
    {"source": "memory", "target": "dreamer"},
    {"source": "dreamer", "target": "realist"},
    {"source": "realist", "target": "skeptic"},
    {"source": "skeptic", "target": "synthesizer"},
    {"source": "synthesizer", "target": "respond"}
  ]
}
```

---

## Visibility: მომხმარებელი რას ხედავს?

### ChatPanel inline activity (engine events → SSE → frontend):

```
┌──────────────────────────────────────────────────┐
│ 🔥 კალციფერი ფიქრობს...                    ▾   │
│                                                  │
│  ✓ ტრიაჟი          — "ეს არის არქიტექტურული"    │
│  ✓ მეხსიერება       — "წინა მსგავსი გადაწყვეტ..." │
│  ✓ ოცნებარი         — "რა იქნება თუ..."          │
│  ▸ რეალისტი         — "ახლა აფასებს..."          │
│  ○ სკეპტიკოსი       — (ელოდება)                  │
│  ○ სინთეზი          — (ელოდება)                  │
└──────────────────────────────────────────────────┘
```

ყოველი node-ის შესრულება = ExecutionStep DB-ში. FlowServer ბროდქასტებს step events-ს EventBroadcaster-ით. ChatController იღებს PubSub-ით და აგზავნის SSE-ით.

### Expanded view (toggle):
```
┌──────────────────────────────────────────────────┐
│ 🔥 კალციფერი ფიქრობს...                    ▴   │
│                                                  │
│  ✓ ტრიაჟი (340ms)                               │
│    "ეს არქიტექტურული გადაწყვეტილებაა:            │
│     მონოლითი vs მიკროსერვისები..."               │
│    tools: classify_topic                         │
│                                                  │
│  ✓ ოცნებარი (2.1s)                               │
│    "რა იქნება თუ event-driven არქიტექტურა        │
│     გამოვიყენოთ CQRS pattern-ით..."              │
│    tools: analyze_flow, list_node_types          │
│                                                  │
│  ▸ რეალისტი (1.4s...)                            │
│    "ვამოწმებ ინფრასტრუქტურის მზაობას..."          │
│    tools: get_flow_graph ← running               │
│                                                  │
│  ○ სკეპტიკოსი                                    │
│  ○ სინთეზი                                       │
└──────────────────────────────────────────────────┘
```

---

## SSE Bridge: FlowServer → ChatController

### პრობლემა
FlowServer = GenServer (ცალკე process). ChatController = request process (ფლობს SSE conn-ს). როგორ მიაღწევს FlowServer-ის events ChatController-ს?

### გადაწყვეტა: Phoenix.PubSub

```
ChatController:
  1. Phoenix.PubSub.subscribe("agent:#{instance_id}")
  2. Start FlowServer for agent flow
  3. receive loop:
     {:step_started, node} → chunk_sse(conn, "activity_step", ...)
     {:step_completed, node, result} → chunk_sse(conn, "activity_step", ...)
     {:instance_completed, result} → chunk_sse(conn, "activity_done", ...)

FlowServer (EventBroadcaster):
  broadcast_node_executed(state, node, result) →
    Phoenix.PubSub.broadcast("agent:#{instance_id}", {:step_completed, ...})
```

EventBroadcaster უკვე არსებობს და broadcast-ებს. ChatController-ს უბრალოდ subscribe ჭირდება.

---

## Agent Work Cycle: ჩვეულებრივი ჩატისთვის

ყოველი ჩატის მესიჯისთვის არ არის საჭირო "ტექ-საბჭო". მარტივი საკითხებისთვის:

```
[intake] → [agent: general_assistant] → [respond]
     (ტრიაჟი)     (chat_with_tools)        (SSE)
```

ეს **მინიმალური agent flow** — 3 node. მაგრამ მაინც engine-ით ორკესტრირებული:
- FlowInstance იქმნება
- ExecutionSteps ილოგება
- Recovery მუშაობს
- Visibility არის

**რთული საკითხებისთვის** (intake-ის ai_decide):
```
[intake] → [ai_decide: complexity?]
              ├─ simple → [agent: assistant] → [respond]
              └─ complex → [dreamer] → [realist] → [skeptic] → [synth] → [respond]
```

---

## Implementation Phases

### Phase 1: `agent` node type
- ai_think-ის extension: `chat_with_tools` support
- Config: system, prompt, model, tools, max_rounds
- ტესტირება: isolated node, dry_run support

### Phase 2: SSE Bridge
- ChatController subscribes to PubSub
- FlowServer (EventBroadcaster) broadcasts step events
- Agent flow-ის გაშვება ChatController-დან

### Phase 3: Frontend ActivityIndicator
- ChatPanel inline component
- Collapsed/expanded toggle
- Real-time step updates via SSE

### Phase 4: Agent Flow Templates
- "Simple assistant" flow (intake → agent → respond)
- "Council" flow (intake → dreamer → realist → skeptic → synth → respond)
- Template registry / selection logic

### Phase 5: Advanced Primitives
- `parallel_group` node
- `sub_flow` node
- `synthesizer` node
- Dynamic routing based on intake classification

---

## ღია კითხვები

1. **Graph cycles:** ახლა engine acyclic graphs-ს ვალიდირებს. Council-ის "loop back to dreamer" ციკლს მოითხოვს. როგორ? — შესაძლოა `max_iterations` ლიმიტით, ან cycle detection-ის relaxation agent flow-ებისთვის.

2. **Streaming from agent node:** agent node-ის შიგნით LLM streaming. FlowServer-ის GenServer-ში stream callback-ი როგორ მუშაობს? — PubSub delta events.

3. **Tool scoping:** სხვადასხვა persona node-ს სხვადასხვა tools. ვინ ამოწმებს რომ "skeptic"-ს არ აქვს `create_flow` ხელმისაწვდომი? — config-ში tools whitelist, agent node ფილტრავს definitions-ს.

4. **Model routing:** სხვადასხვა node-ს სხვადასხვა model. ვინ ფლობს API key-ებს? — tenant AI config (უკვე არსებობს), node config-ში model override.

5. **Cost control:** 5 node × multi-round agent = ბევრი API call. Limit? — config-ში max_rounds per node + flow-level budget (total tokens/calls).
