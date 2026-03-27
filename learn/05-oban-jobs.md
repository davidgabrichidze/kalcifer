# Oban — PostgreSQL-Based Job Queue

## Context: Why Oban Matters in Kalcifer

Kalcifer's flow engine needs reliable background processing for: resuming waiting flow instances after a delay, delivering messages through channels (email, SMS, push), running maintenance tasks (cleanup, stats rollup), and recovering from crashes. Oban provides all of this on top of PostgreSQL — no Redis, no RabbitMQ, no extra infrastructure.

## Why Oban Instead of Redis-Based Queues (Sidekiq, Bull, etc.)

1. **Transactional guarantees**: Oban jobs are inserted in the same PostgreSQL transaction as your business data. If you create a FlowInstance and schedule a ResumeFlowJob in the same transaction, either both happen or neither does. Redis-based queues can't guarantee this.

2. **No extra infrastructure**: PostgreSQL is already your primary database. Oban uses it for the job queue via LISTEN/NOTIFY for real-time notification and polling as fallback.

3. **Cluster-safe**: Multiple Oban instances across nodes share the same PostgreSQL queue. Jobs are locked per-node using PostgreSQL advisory locks. No need for Redis Sentinel or cluster configuration.

4. **First-class Elixir**: Oban jobs are Elixir modules with structured args, not serialized strings. Type safety, pattern matching, and the full BEAM toolset available in workers.

## Architecture

```
PostgreSQL (oban_jobs table)
  ├── Queue: flow_triggers (10 workers)     ← triggering flow instances
  ├── Queue: delayed_resume (20 workers)    ← resuming waiting instances after delay
  ├── Queue: channel_delivery (50 workers)  ← sending emails, SMS, push, etc.
  └── Queue: maintenance (5 workers)        ← cleanup, stats rollup

Oban Process (per Elixir node):
  ├── Producer: polls/listens for available jobs
  ├── Workers: execute jobs concurrently (bounded by queue limit)
  └── Plugins: Pruner (cleanup old jobs), Cron (scheduled jobs)
```

## Configuration

```elixir
# config/config.exs
config :kalcifer, Oban,
  repo: Kalcifer.Repo,
  queues: [
    flow_triggers: 10,
    delayed_resume: 20,
    channel_delivery: 50,
    maintenance: 5
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},  # 7 days
    {Oban.Plugins.Cron, crontab: [
      {"0 3 * * *", Kalcifer.Engine.Jobs.CleanupJob},           # Daily 03:00 UTC
      {"*/5 * * * *", Kalcifer.Engine.Jobs.StatsRollupJob}      # Every 5 minutes
    ]}
  ]

# config/test.exs — CRITICAL for testing
config :kalcifer, Oban,
  testing: :manual  # Jobs are inserted but NOT executed automatically
```

**Underwater Rock**: The `testing: :manual` mode is essential. In tests, jobs are stored in the database but never picked up by workers. You assert on their existence or manually execute them. Without this, tests would fire off real jobs (sending emails, hitting APIs).

## Writing Workers

```elixir
defmodule Kalcifer.Engine.Jobs.ResumeFlowJob do
  use Oban.Worker,
    queue: :delayed_resume,
    max_attempts: 3,
    unique: [period: 60, fields: [:args]]  # Deduplicate within 60 seconds

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"instance_id" => instance_id, "node_id" => node_id} = args

    case Kalcifer.Engine.resume_instance(instance_id, node_id) do
      :ok -> :ok
      {:error, :instance_not_found} -> :discard  # Don't retry, instance was deleted
      {:error, reason} -> {:error, reason}  # Will retry up to max_attempts
    end
  end
end
```

### Return Values

```elixir
# Success — job marked as completed
:ok

# Snooze — retry after N seconds (useful for rate limiting)
{:snooze, 30}

# Discard — give up, mark as discarded (won't retry)
:discard

# Error — retry according to max_attempts with backoff
{:error, reason}

# Cancel — explicitly cancel (different from discard semantically)
{:cancel, reason}
```

### Scheduling Jobs

```elixir
# Insert a job to run immediately
%{instance_id: instance_id, node_id: node_id}
|> ResumeFlowJob.new()
|> Oban.insert()

# Schedule for later (e.g., wait node with 3-hour delay)
%{instance_id: instance_id, node_id: node_id}
|> ResumeFlowJob.new(scheduled_at: DateTime.add(DateTime.utc_now(), 3 * 3600, :second))
|> Oban.insert()

# Insert within a transaction (key Kalcifer pattern!)
Ecto.Multi.new()
|> Ecto.Multi.update(:instance, instance_changeset)
|> Oban.insert(:resume_job, ResumeFlowJob.new(%{
  instance_id: instance.id,
  node_id: next_node_id
}))
|> Repo.transaction()
```

**Key Pattern**: When a flow instance reaches a wait node, Kalcifer updates the instance status to "waiting" AND inserts a ResumeFlowJob with a scheduled_at in the same transaction. If the DB transaction fails, neither the status update nor the job is created. This guarantees consistency.

## Uniqueness and Deduplication

```elixir
use Oban.Worker,
  unique: [
    period: 300,               # 5 minutes
    fields: [:args, :queue],   # Unique by args + queue combination
    states: [:available, :scheduled, :executing]  # Check against these states
  ]
```

**Why this matters in Kalcifer**: If a customer triggers the same flow twice within seconds, you don't want two ResumeFlowJobs for the same instance. Uniqueness constraints prevent duplicate processing.

**Underwater Rock**: Uniqueness is enforced at INSERT time, not execution time. If two nodes of code race to insert the same unique job, one succeeds and the other returns the existing job. Check the return value: `{:ok, job}` vs `{:ok, %{conflict?: true}}`.

## Retry and Backoff

```elixir
use Oban.Worker,
  max_attempts: 5,
  # Default backoff: exponential with jitter
  # Attempt 1: ~0s, Attempt 2: ~4s, Attempt 3: ~16s, Attempt 4: ~64s, Attempt 5: ~256s

# Custom backoff
@impl Oban.Worker
def backoff(%Oban.Job{attempt: attempt}) do
  # Linear backoff: 30 seconds between attempts
  30
end
```

**Underwater Rock**: After all attempts are exhausted, the job moves to the "discarded" state. It stays in the database (until the Pruner cleans it up). Monitor discarded jobs in production — they indicate systematic failures.

## Cron Jobs

```elixir
# Configured in Oban config
{Oban.Plugins.Cron, crontab: [
  {"0 3 * * *", Kalcifer.Engine.Jobs.CleanupJob},        # 3 AM UTC daily
  {"*/5 * * * *", Kalcifer.Engine.Jobs.StatsRollupJob}    # Every 5 minutes
]}

# CleanupJob might:
# - Archive old completed instances
# - Delete expired sessions
# - Prune orphaned execution steps

# StatsRollupJob might:
# - Aggregate per-flow conversion metrics
# - Calculate funnel statistics
# - Update dashboard counters
```

**Underwater Rock**: Cron jobs run on ONE node in the cluster (Oban's leader election via PostgreSQL ensures this). You don't get duplicate cron executions across nodes.

## Testing Oban Jobs

```elixir
# In test.exs: testing: :manual
# This means: jobs are stored but not auto-executed

defmodule Kalcifer.Engine.Jobs.ResumeFlowJobTest do
  use Kalcifer.DataCase
  use Oban.Testing, repo: Kalcifer.Repo

  test "resumes a waiting instance" do
    instance = insert(:flow_instance, status: "waiting")

    # Manually perform the job (doesn't go through the queue)
    assert :ok = perform_job(ResumeFlowJob, %{
      "instance_id" => instance.id,
      "node_id" => "node_1"
    })

    # Verify the instance was resumed
    updated = Repo.get!(FlowInstance, instance.id)
    assert updated.status == "running"
  end

  test "schedules a resume job when wait node is reached" do
    # Execute flow until it hits a wait node
    trigger_flow(flow)

    # Assert the job was enqueued (not executed, just stored)
    assert_enqueued(
      worker: ResumeFlowJob,
      args: %{"instance_id" => instance.id, "node_id" => "wait_1"}
    )
  end

  test "discards job when instance not found" do
    assert :discard = perform_job(ResumeFlowJob, %{
      "instance_id" => Ecto.UUID.generate(),
      "node_id" => "node_1"
    })
  end
end
```

**Testing helpers provided by Oban:**
- `assert_enqueued/1` — verify a job was inserted with specific args
- `refute_enqueued/1` — verify no such job exists
- `perform_job/2` — execute a worker synchronously in the test process
- `all_enqueued/1` — list all enqueued jobs matching criteria

**Underwater Rock**: `perform_job/2` runs the worker's `perform/1` directly in the test process. It does NOT go through the queue. This means uniqueness constraints, max_attempts, and backoff are NOT tested. Test those behaviors separately or use Oban's `:inline` mode (which processes jobs synchronously but through the full pipeline).

## Monitoring in Production

```elixir
# Oban emits telemetry events:
# [:oban, :job, :start]     — job began executing
# [:oban, :job, :stop]      — job completed successfully
# [:oban, :job, :exception] — job raised an error

# Attach handlers for monitoring:
:telemetry.attach("oban-errors", [:oban, :job, :exception], fn event, measurements, meta, _ ->
  Logger.error("Oban job failed",
    worker: meta.worker,
    queue: meta.queue,
    attempt: meta.attempt,
    error: inspect(meta.reason)
  )
end, nil)
```

## How Oban Fits in Kalcifer's Flow Lifecycle

```
1. API request triggers flow
   → Engine starts FlowServer GenServer
   → FlowServer executes nodes synchronously

2. Flow reaches wait node (e.g., "wait 3 hours")
   → FlowServer persists state to DB (status: "waiting")
   → Inserts ResumeFlowJob with scheduled_at = now + 3h (same transaction)
   → FlowServer process terminates (frees memory)

3. After 3 hours, Oban picks up ResumeFlowJob
   → Job starts new FlowServer for the instance
   → FlowServer loads state from DB
   → Execution continues from the wait node

4. Flow reaches send_email action
   → FlowServer inserts SendMessageJob into channel_delivery queue
   → SendMessageJob calls channel provider (email API)
   → Delivery status tracked in deliveries table

5. Flow completes
   → FlowServer sets instance status to "completed"
   → Process terminates
```

## Key Takeaways

1. Oban turns PostgreSQL into a job queue — no extra infrastructure.
2. Transactional job insertion guarantees consistency with business data.
3. `testing: :manual` mode makes jobs fully testable without side effects.
4. Uniqueness prevents duplicate job processing.
5. Cron jobs run on a single node via leader election.
6. Jobs are the bridge between GenServer process lifecycle and persistent scheduling.

## Recommended Resources

- Oban documentation: hexdocs.pm/oban
- "Reliable job processing in Elixir with Oban" — Oban guides
- Oban Web (commercial dashboard) documentation for monitoring patterns
- Blog: "Replacing Sidekiq with Oban" comparisons for context
