# Elixir Language — Fast Track for Experienced Developers

## Context: Why Elixir for This Project

Kalcifer is a flow orchestration engine that needs to manage thousands of concurrent long-running processes, each representing a customer journey. Elixir runs on the BEAM virtual machine (Erlang's VM), which was designed for telecom systems that needed 99.999% uptime. The BEAM gives you: lightweight processes (not OS threads), preemptive scheduling, per-process garbage collection, and hot code reloading. These aren't nice-to-haves for Kalcifer — they're architectural requirements.

## What You Already Know (Mapping)

If you know Ruby: Elixir's syntax is Ruby-inspired. José Valim (Elixir creator) was a Rails core team member. But under the hood it's completely different — functional, immutable, compiled to BEAM bytecode.

If you know Go: Think of goroutines but with built-in supervision, crash recovery, and message passing (no shared memory). Elixir processes are even lighter than goroutines.

If you know Java: Think of each Elixir process as a lightweight actor (like Akka actors, but baked into the runtime). No synchronized blocks, no locks, no shared mutable state.

If you know Python: The functional paradigm will be the biggest shift. No classes, no mutation, no for-loops in the traditional sense. Everything returns a value.

## Core Concepts That Matter for Kalcifer

### 1. Pattern Matching (Used Everywhere)

Pattern matching is not just syntax sugar — it's how you write control flow, destructure data, and handle different cases. In Kalcifer, every node's execute function uses pattern matching to handle different outcomes.

```elixir
# This is NOT assignment — it's pattern matching
{:ok, result} = some_function()  # Crashes if function returns {:error, _}

# Multi-clause functions — the runtime picks the matching clause
def handle_result({:completed, result}), do: move_to_next_node(result)
def handle_result({:waiting, config}), do: pause_and_schedule(config)
def handle_result({:failed, reason}), do: mark_failed(reason)

# In Kalcifer's node executor, this pattern dispatches execution results
case node_module.execute(config, context) do
  {:completed, result} -> # advance graph
  {:branched, branch_key, result} -> # follow specific edge
  {:waiting, wait_config} -> # park the instance
  {:failed, reason} -> # error handling
end
```

**Underwater Rock**: Pattern matching happens left-to-right, top-to-bottom. Order of function clauses matters. Put more specific patterns before general ones. The compiler warns you about unreachable clauses — listen to it.

### 2. Pipe Operator |> (Elixir's Signature)

The pipe passes the result of one expression as the first argument to the next function. It transforms nested calls into readable pipelines.

```elixir
# Without pipe (hard to read)
String.trim(String.downcase(String.replace(input, " ", "_")))

# With pipe (reads like a recipe)
input
|> String.replace(" ", "_")
|> String.downcase()
|> String.trim()

# In Kalcifer — building a query pipeline
FlowInstance
|> where([i], i.status == "waiting")
|> where([i], i.tenant_id == ^tenant_id)
|> Repo.all()
```

**Underwater Rock**: The pipe always passes to the FIRST argument. If you need to pass to a different position, use an anonymous function: `value |> then(fn v -> Map.put(map, :key, v) end)`.

### 3. Immutability and Data Transformation

Nothing mutates in Elixir. You always create new data. This sounds expensive but the BEAM optimizes structural sharing.

```elixir
# "Updating" a map creates a new map
context = %{customer_id: "abc", accumulated: %{}}
new_context = Map.put(context, :step_count, 1)
# context is unchanged, new_context has the new key

# Map update syntax (for existing keys only)
context = %{context | accumulated: %{email_sent: true}}

# In Kalcifer — context accumulation through node execution
defp update_context(context, node_result) do
  accumulated = Map.get(context, :accumulated, %{})
  new_accumulated = Map.merge(accumulated, node_result)
  %{context | accumulated: new_accumulated}
end
```

**Underwater Rock**: The `%{map | key: value}` syntax ONLY works for existing keys. It will crash if the key doesn't exist. Use `Map.put/3` for adding new keys.

### 4. Modules and Structs (Not Classes)

Elixir has no classes. Modules group functions and can define structs (typed maps).

```elixir
defmodule Kalcifer.Flows.Flow do
  use Ecto.Schema

  schema "flows" do
    field :name, :string
    field :status, :string, default: "draft"
    field :description, :string
    belongs_to :tenant, Kalcifer.Tenants.Tenant
    has_many :versions, Kalcifer.Flows.FlowVersion
    timestamps(type: :utc_datetime)
  end
end

# Modules are just namespaces for functions
defmodule Kalcifer.Flows do
  def create_flow(attrs) do
    %Flow{}
    |> Flow.changeset(attrs)
    |> Repo.insert()
  end

  def get_flow!(id), do: Repo.get!(Flow, id)
end
```

**Underwater Rock**: Elixir modules are NOT objects. `Kalcifer.Flows.Flow` is just a namespace. There's no inheritance, no method dispatch, no `self`. Polymorphism is achieved through behaviours (interfaces) and protocols.

### 5. Behaviours (Interfaces)

Behaviours define a set of callbacks a module must implement. Kalcifer's entire node system is built on NodeBehaviour.

```elixir
defmodule Kalcifer.Engine.Nodes.NodeBehaviour do
  @callback execute(config :: map(), context :: map()) ::
    {:completed, map()} |
    {:branched, String.t(), map()} |
    {:waiting, map()} |
    {:failed, String.t()}

  @callback resume(config :: map(), context :: map(), trigger :: map()) ::
    {:completed, map()} | {:branched, String.t(), map()} | {:failed, String.t()}

  @callback validate(config :: map()) :: :ok | {:error, [String.t()]}
  @callback config_schema() :: map()
  @callback category() :: :trigger | :condition | :wait | :action | :end

  @optional_callbacks [resume: 3, validate: 1]
end

# A node implements the behaviour
defmodule Kalcifer.Engine.Nodes.Action.Channel.SendEmail do
  @behaviour Kalcifer.Engine.Nodes.NodeBehaviour

  @impl true
  def execute(config, context) do
    # ... send email logic
    {:completed, %{email_sent: true, message_id: msg_id}}
  end

  @impl true
  def category, do: :action

  @impl true
  def config_schema, do: %{to: :string, subject: :string, body: :string}
end
```

**Underwater Rock**: `@impl true` is optional but critical for catching bugs. If you typo a callback name, without `@impl` you just get a regular function that's never called. With `@impl`, the compiler catches it.

### 6. Processes and Message Passing (Preview — Deep Dive in OTP Guide)

Every Elixir process has a mailbox. Processes communicate by sending messages.

```elixir
# Spawn a process
pid = spawn(fn ->
  receive do
    {:hello, sender} -> send(sender, :world)
  end
end)

# Send it a message
send(pid, {:hello, self()})

# Receive the reply
receive do
  :world -> IO.puts("Got reply!")
end
```

In Kalcifer, you almost never use raw `spawn` — you use GenServer (covered in the OTP guide). But understanding that processes are the unit of concurrency is essential.

### 7. Error Handling Philosophy

Elixir uses two approaches:

```elixir
# Pattern 1: Tagged tuples (expected failures)
case Repo.insert(changeset) do
  {:ok, record} -> # success path
  {:error, changeset} -> # validation failed — handle it
end

# Pattern 2: Let it crash (unexpected failures)
# If get_flow! can't find the record, it raises — and the supervisor restarts the process
flow = Flows.get_flow!(flow_id)
```

**Underwater Rock**: Functions ending in `!` raise exceptions. Functions without `!` return tagged tuples. `Repo.get/2` returns `nil` on miss; `Repo.get!/2` raises. In Kalcifer, the `!` versions are used inside GenServers where a crash triggers supervisor recovery.

### 8. Comprehensions and Enum

```elixir
# Enum module — your bread and butter
nodes = Enum.filter(graph.nodes, fn node -> node.category == :action end)
names = Enum.map(nodes, & &1.name)  # capture syntax: & &1 means "first argument"

# Comprehension — more powerful
for node <- graph.nodes,
    node.category == :action,
    node.status == :active do
  execute_node(node)
end

# Reduce — accumulating results (used heavily in graph traversal)
Enum.reduce(execution_steps, initial_context, fn step, ctx ->
  Map.merge(ctx, step.result)
end)
```

### 9. With Statement (Happy Path Chaining)

```elixir
# Instead of nested case statements
with {:ok, flow} <- Flows.get_flow(flow_id),
     {:ok, version} <- Flows.get_active_version(flow),
     {:ok, instance} <- Engine.start_instance(version, context) do
  {:ok, instance}
else
  {:error, :not_found} -> {:error, "Flow not found"}
  {:error, :no_active_version} -> {:error, "No active version"}
  {:error, reason} -> {:error, reason}
end
```

**Underwater Rock**: `with` only matches the patterns you specify. If a step returns something unexpected (like `:error` without a tuple), it falls through to `else`. Always have a catch-all in `else`.

## Elixir Conventions Used in Kalcifer

1. **Snake_case everywhere**: module functions, variables, file names. Modules are CamelCase.
2. **Contexts pattern**: `Kalcifer.Flows` is a context module — the public API for flow operations. Controllers call contexts, never schemas directly.
3. **Alias ordering**: Alphabetical (enforced by Credo strict). Not optional.
4. **120 char line limit**: Enforced by formatter and Credo.
5. **No @doc on private functions**: Causes compiler warnings with --warnings-as-errors.

## What to Practice

1. Rewrite a familiar algorithm using pattern matching and recursion (no loops)
2. Build a data transformation pipeline using |> with Enum functions
3. Implement a behaviour with 3 callback functions and 2 implementing modules
4. Practice destructuring nested maps with pattern matching
5. Use `with` to chain 4+ fallible operations

## Recommended Resources

- Elixir official Getting Started guide (elixir-lang.org/getting-started)
- "Elixir in Action" by Saša Jurić — best for experienced developers
- "Programming Elixir" by Dave Thomas — thorough language reference
- Exercism.io Elixir track — for hands-on practice
