# Kalcifer Technology Learning Roadmap

## Who This Is For

You are a professional programmer or software architect learning the Elixir/OTP ecosystem to work on Kalcifer — a flow orchestration engine built for production marketing automation. These materials assume you already know at least one backend language well (Python, Java, Go, Node.js, etc.) and understand concepts like databases, HTTP APIs, concurrency, and distributed systems.

## How to Use These Files with Google NotebookLM

Upload all files from this `learn/` folder into a single NotebookLM notebook. Each file covers one technology pillar. NotebookLM will cross-reference them and let you ask questions that span multiple topics. For example: "How does FlowServer use Ecto to persist state?" will draw from both the OTP and Ecto guides.

## Learning Order (Critical Path)

### Phase 1: Language Foundations (Days 1-3)
**File: `01-elixir-language.md`**
Elixir syntax, pattern matching, pipe operator, modules, immutability. If you know Ruby or any functional language, this phase is fast. If you come from Java/Go, spend extra time on pattern matching and the pipe operator — they fundamentally change how you structure code.

### Phase 2: OTP & Concurrency (Days 3-7)
**File: `02-otp-concurrency.md`**
This is the single most important topic. GenServer, Supervisors, DynamicSupervisor, Registry, ETS. Kalcifer's entire engine is built on OTP patterns. A flow instance IS a GenServer process. Understanding this is non-negotiable.

### Phase 3: Phoenix API Layer (Days 7-9)
**File: `03-phoenix-api.md`**
Phoenix as an API-only framework. Routers, controllers, plugs, JSON responses. Kalcifer uses no HTML/LiveView — it's a pure API server. If you've used Express.js, Django REST, or Gin, this maps directly.

### Phase 4: Ecto & PostgreSQL (Days 9-12)
**File: `04-ecto-postgresql.md`**
Ecto is NOT an ORM — it's a toolkit. Schemas, changesets, queries, migrations, multi-tenancy patterns. Kalcifer uses binary_id (UUID) primary keys, Ecto.Multi for transactional operations, and SQL Sandbox for test isolation.

### Phase 5: Oban Job Queue (Days 12-14)
**File: `05-oban-jobs.md`**
Background job processing built on PostgreSQL. Why Oban instead of Redis-based queues, how jobs relate to flow resumption, cron scheduling, and the manual testing mode that makes Oban testable.

### Phase 6: Testing Ecosystem (Days 14-16)
**File: `06-testing.md`**
ExUnit, ExMachina factories, Mox for behavior-based mocking, StreamData for property testing, Ecto SQL Sandbox for concurrent test isolation. Kalcifer's test patterns are non-trivial because they involve GenServers, Oban jobs, and ETS tables.

### Phase 7: Architecture Deep-Dive (Days 16-20)
**File: `07-architecture-patterns.md`**
Process-per-instance, plugin node system, event-driven resumption, circuit breaker, crash recovery. This ties everything together and explains WHY Kalcifer is built the way it is.

### Phase 8: Production Concerns (Days 20-22)
**File: `08-production.md`**
Deployment, clustering (libcluster, dns_cluster), telemetry, structured logging, release configuration, health checks, and operational patterns.

## Key Mental Model Shifts

### From Object-Oriented to Functional+Process
In OOP, you have objects with mutable state. In Elixir/OTP, you have processes (lightweight threads) that hold state and communicate via messages. A FlowInstance isn't a class instance — it's a running process with its own mailbox, crash isolation, and lifecycle.

### From Framework-Driven to Library-Composed
Elixir projects compose libraries rather than extending a monolithic framework. Phoenix handles HTTP, Ecto handles data, Oban handles jobs — they're independent and you wire them together in your application supervision tree.

### From Defensive Programming to "Let It Crash"
Instead of try/catch everywhere, you design supervision trees that restart failed processes automatically. RecoveryManager in Kalcifer literally restarts crashed flow instances on boot.

### From Connection Pools to Process Pools
Database connections are pooled (Ecto), but computation is parallelized via lightweight BEAM processes. Spawning 10,000 processes costs almost nothing. Each flow instance runs in its own process.

## What Makes This Project Non-Trivial

Kalcifer uses almost every serious OTP pattern: DynamicSupervisor for runtime process creation, ETS for fast registry lookups, GenServer for stateful long-running processes, PubSub for event broadcasting, and Oban for reliable background jobs. It also integrates multi-provider AI (Anthropic, OpenAI, Google), circuit breaker patterns for channel delivery, and a plugin-style node system that allows runtime extension. This is not a CRUD app — it's an orchestration engine.
