# OTP & Concurrency — The Heart of Kalcifer

## Why This Is the Most Important Chapter

Kalcifer's engine runs each flow instance as a separate process. When 5,000 customers are simultaneously in different stages of a marketing journey, there are 5,000 GenServer processes running concurrently, each with its own state, each supervised, each capable of crashing and recovering independently. If you don't understand OTP, you can't understand Kalcifer.

## BEAM Processes — Not What You Think

BEAM processes are NOT OS threads. They are:
- Extremely lightweight (~2KB initial memory, vs ~1MB for OS threads)
- Preemptively scheduled by the BEAM (no cooperative yielding needed)
- Garbage collected independently (no stop-the-world GC)
- Completely isolated (no shared memory, crash in one doesn't affect others)

You can comfortably run millions of processes on a single machine. Kalcifer relies on this for its process-per-instance architecture.

## GenServer — The Workhorse

GenServer is a behaviour that abstracts the receive loop into callbacks. It's the most used OTP pattern.

### Mental Model

Think of a GenServer as a single-threaded actor with a mailbox:
1. It holds state (a single Elixir term — usually a map or struct)
2. It receives messages one at a time (serialized)
3. Each message handler returns the new state
4. It runs in its own process, isolated from everything else

### The Three Core Callbacks

```elixir
defmodule Kalcifer.Engine.FlowServer do
  use GenServer

  # --- Client API (called from other processes) ---

  def start_link(opts) do
    instance_id = Keyword.fetch!(opts, :instance_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(instance_id))
  end

  def get_state(instance_id) do
    GenServer.call(via_tuple(instance_id), :get_state)
  end

  def resume(instance_id, node_id, event_data) do
    GenServer.cast(via_tuple(instance_id), {:resume, node_id, event_data})
  end

  # --- Server Callbacks (run inside the GenServer process) ---

  # init/1 — called when process starts, returns initial state
  @impl true
  def init(opts) do
    instance_id = Keyword.fetch!(opts, :instance_id)
    # Load instance from DB, set up state
    state = %{
      instance_id: instance_id,
      graph: load_graph(instance_id),
      context: load_context(instance_id),
      execution_count: 0
    }
    {:ok, state}
  end

  # handle_call/3 — synchronous request-response (caller waits)
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}  # {reply, response_to_caller, new_state}
  end

  # handle_cast/2 — asynchronous fire-and-forget
  @impl true
  def handle_cast({:resume, node_id, event_data}, state) do
    new_state = execute_from_node(node_id, event_data, state)
    {:noreply, new_state}  # {noreply, new_state}
  end
end
```

### call vs cast — When to Use Which

**call (synchronous)**: Use when the caller needs a response. The caller blocks until the GenServer replies. Example: `get_state/1` — the API controller needs the state to return it in a JSON response.

**cast (asynchronous)**: Use when the caller doesn't need to wait. Example: `resume/3` — the event router fires a resume and moves on. The flow executes in its own time.

**Underwater Rock**: `call` has a default timeout of 5 seconds. If the GenServer is busy (executing a long node), the caller gets a timeout crash. In Kalcifer, resume uses `cast` specifically to avoid this — flow execution can take arbitrary time.

**Underwater Rock**: Never call a GenServer from within itself (deadlock). If `handle_call` needs to trigger another operation on the same server, use `send(self(), :some_message)` and handle it in `handle_info`.

### handle_info — Handling Raw Messages

```elixir
# handle_info catches messages not sent via call/cast
@impl true
def handle_info(:timeout, state) do
  # Process has been idle, maybe checkpoint state to DB
  {:noreply, state}
end

@impl true
def handle_info({:execute_next, node_id}, state) do
  # Internal message — triggered by send(self(), ...)
  new_state = execute_node(node_id, state)
  {:noreply, new_state}
end
```

**Underwater Rock**: Unhandled messages in `handle_info` are silently dropped (with a log warning). Always add a catch-all clause for debugging:
```elixir
def handle_info(msg, state) do
  Logger.warning("Unexpected message: #{inspect(msg)}")
  {:noreply, state}
end
```

## Supervisors — Crash Recovery Architecture

### The "Let It Crash" Philosophy

Instead of wrapping every operation in try/catch, you design your system so that:
1. Each critical piece of state lives in a supervised process
2. If that process crashes, its supervisor restarts it
3. The restarted process initializes from persistent state (database)

This is not lazy error handling — it's a design pattern. Erlang systems (telecom switches) achieved 99.9999999% uptime with this approach.

### Supervisor Strategies

```elixir
# one_for_one: If one child crashes, only restart that child
# Used for: Independent processes (most common)
children = [
  {Kalcifer.Repo, []},
  {Phoenix.PubSub, name: Kalcifer.PubSub},
  {Oban, oban_config()}
]
Supervisor.start_link(children, strategy: :one_for_one)

# rest_for_one: If one crashes, restart it AND all children started after it
# Used for: Kalcifer's Engine.Supervisor (dependencies flow downward)
children = [
  Kalcifer.Engine.LogCollector,        # 1. Log infrastructure
  {Registry, keys: :unique, name: ProcessRegistry},  # 2. Process registry
  Kalcifer.Engine.NodeRegistry,         # 3. Node type registry (needs Registry)
  Kalcifer.Engine.ProviderRegistry,     # 4. Channel providers (needs NodeRegistry)
  {DynamicSupervisor, name: FlowSupervisor},  # 5. Flow processes (needs everything above)
  Kalcifer.Engine.RecoveryManager       # 6. Restarts crashed instances (needs DynamicSupervisor)
]
Supervisor.start_link(children, strategy: :rest_for_one)

# one_for_all: If one crashes, restart ALL children
# Used for: Tightly coupled processes that share state assumptions
```

**Why rest_for_one for the Engine?** If NodeRegistry crashes and restarts, the DynamicSupervisor's FlowServer processes might reference stale node modules. By using rest_for_one, crashing NodeRegistry also restarts everything after it (ProviderRegistry, FlowSupervisor, RecoveryManager), ensuring consistency.

### DynamicSupervisor — Runtime Process Creation

Regular Supervisors have a fixed set of children defined at start. DynamicSupervisor starts children on demand — perfect for flow instances that come and go.

```elixir
# Starting a new flow instance at runtime
DynamicSupervisor.start_child(
  Kalcifer.Engine.FlowSupervisor,
  {Kalcifer.Engine.FlowServer, instance_id: instance_id, graph: graph}
)

# The DynamicSupervisor manages these children:
# - Monitors them
# - Restarts them if they crash (within restart limits)
# - Can enumerate them (DynamicSupervisor.which_children/1)
```

**Underwater Rock**: DynamicSupervisor has restart intensity limits (default: 3 restarts in 5 seconds). If a child keeps crashing, the supervisor itself crashes (escalating to its parent). This prevents infinite restart loops. Kalcifer's RecoveryManager handles the initial restart from DB state — if the GenServer keeps crashing after recovery, something is fundamentally wrong and escalation is correct.

## Registry — Process Discovery

How do you find a specific FlowServer process among thousands? By name, using Elixir's Registry.

```elixir
# Registration happens at start_link time
def start_link(opts) do
  instance_id = Keyword.fetch!(opts, :instance_id)
  GenServer.start_link(__MODULE__, opts,
    name: {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}
  )
end

# Lookup by instance_id from anywhere
def via_tuple(instance_id) do
  {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}
end

# Send a message to a specific flow instance
GenServer.cast(via_tuple("instance-abc-123"), {:resume, node_id, data})
```

**Key insight**: Registry is a local (single-node) lookup. For multi-node clusters, Kalcifer uses PubSub broadcasting and Oban jobs (which are database-backed and thus cluster-wide).

## ETS — In-Memory Key-Value Storage

ETS (Erlang Term Storage) is shared memory between processes on the same node. It's used when you need fast reads that don't serialize through a single GenServer.

### Kalcifer's ETS Usage

```elixir
# NodeRegistry — maps string type names to modules
defmodule Kalcifer.Engine.NodeRegistry do
  use GenServer

  def init(_) do
    table = :ets.new(:node_registry, [:set, :named_table, :public, read_concurrency: true])
    register_built_in_nodes(table)
    {:ok, %{table: table}}
  end

  def lookup(type) do
    case :ets.lookup(:node_registry, type) do
      [{^type, module}] -> {:ok, module}
      [] -> {:error, :not_found}
    end
  end

  def register(type, module) do
    :ets.insert(:node_registry, {type, module})
    :ok
  end
end
```

**Why ETS instead of a GenServer holding a map?**
- ETS reads are concurrent — multiple processes can read simultaneously without serialization
- GenServer calls serialize — if 1000 processes all need to look up node types, they'd queue up
- ETS with `read_concurrency: true` is optimized for exactly this pattern

**Underwater Rock**: ETS tables are owned by the process that created them. If that process dies, the table is deleted. That's why NodeRegistry is a GenServer under a supervisor — if it crashes, the supervisor restarts it, and init recreates and repopulates the table.

**Underwater Rock**: ETS persists data for the lifetime of the owning process. In tests, if you insert entries, they stay until the test process ends. Kalcifer's CLAUDE.md explicitly warns: use `>= N` assertions, not `== N` for ETS counts.

## Process Links and Monitors

### Links (Bidirectional Crash Propagation)

```elixir
# If either process crashes, both crash
Process.link(pid)

# Supervisors use links — that's how they know when children crash
# When you start_link a GenServer, it's linked to the caller (the supervisor)
```

### Monitors (Unidirectional Crash Notification)

```elixir
# If the monitored process crashes, we get a message (but we don't crash)
ref = Process.monitor(pid)

# We'll receive:
# {:DOWN, ^ref, :process, ^pid, reason}

# Used in Kalcifer's EventRouter to know when flow instances terminate
```

**Underwater Rock**: Links are symmetric — they kill both sides. Monitors are one-way. Use monitors when you need to react to a crash without dying yourself.

## Task — Short-Lived Async Work

```elixir
# Fire and forget
Task.start(fn -> send_analytics_event(data) end)

# Async with result
task = Task.async(fn -> expensive_computation() end)
result = Task.await(task, 30_000)  # 30 second timeout

# Multiple tasks in parallel
tasks = Enum.map(nodes, fn node ->
  Task.async(fn -> validate_node(node) end)
end)
results = Task.await_many(tasks, 10_000)
```

Kalcifer's RecoveryManager uses Task to scan for crashed instances on boot without blocking the supervisor startup.

## Phoenix.PubSub — Inter-Process Broadcasting

```elixir
# Subscribe to a topic
Phoenix.PubSub.subscribe(Kalcifer.PubSub, "flow:#{flow_id}")

# Broadcast to all subscribers
Phoenix.PubSub.broadcast(Kalcifer.PubSub, "flow:#{flow_id}", {:instance_completed, instance_id})

# In a GenServer's handle_info:
def handle_info({:instance_completed, instance_id}, state) do
  # React to instance completion
  {:noreply, state}
end
```

PubSub works across cluster nodes (via Phoenix.PubSub.PG2 adapter). This is how Kalcifer can route events even when the target FlowServer is on a different node.

## Putting It Together: Kalcifer's Engine Lifecycle

1. **Application starts** → Top-level Supervisor starts Engine.Supervisor
2. **Engine.Supervisor (rest_for_one)** starts: LogCollector → Registry → NodeRegistry → ProviderRegistry → DynamicSupervisor → RecoveryManager
3. **RecoveryManager** queries DB for instances with status "waiting" or "running", starts FlowServer for each via DynamicSupervisor
4. **API request arrives** to trigger a flow → Controller calls Engine → Engine starts new FlowServer via DynamicSupervisor
5. **FlowServer.init** loads graph and context from DB, begins execution
6. **Execution reaches a wait node** → FlowServer sets status to "waiting", schedules Oban job for timeout
7. **Event arrives** → EventRouter looks up waiting instances by customer_id, sends resume cast to FlowServer
8. **FlowServer crashes** → DynamicSupervisor restarts it → init reloads state from DB → continues from last checkpoint
9. **Execution completes** → FlowServer sets status to "completed", process terminates normally

## Common Mistakes for Newcomers

1. **Putting too much in one GenServer**: If one GenServer handles all flow instances, it becomes a bottleneck. Kalcifer correctly uses one GenServer per instance.

2. **Forgetting that GenServer calls are serialized**: If handle_call does a database query that takes 2 seconds, ALL other calls to that GenServer wait. Keep handlers fast. Offload slow work to Tasks or Oban jobs.

3. **Not considering what happens on restart**: Every GenServer must be able to reconstruct its state from persistent storage (DB) in init/1. Never rely solely on in-memory state.

4. **Using GenServer for read-heavy data**: If many processes need to read the same data, use ETS with read_concurrency. GenServer serializes all access.

5. **Blocking in init/1**: If init does heavy work (network calls, complex queries), supervisor startup slows down. Use `{:ok, state, {:continue, :setup}}` and `handle_continue/2` for deferred initialization.

## Recommended Resources

- "Elixir in Action" by Saša Jurić, chapters 5-12 (the OTP section)
- "Designing Elixir Systems with OTP" by James Edward Gray II & Bruce Tate
- The Little Elixir & OTP Guidebook by Benjamin Tan Wei Hao
- Official GenServer documentation: hexdocs.pm/elixir/GenServer.html
