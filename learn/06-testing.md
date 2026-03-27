# Testing Ecosystem — ExUnit, ExMachina, Mox, StreamData

## Context: Why Testing in Kalcifer Is Non-Trivial

Testing a flow orchestration engine means testing: GenServer processes that hold state, Oban jobs that run asynchronously, ETS tables that persist across tests, database transactions with concurrent access, and event-driven resumption flows. The standard "call function, assert result" approach isn't enough. Kalcifer uses four testing libraries together to handle this complexity.

## ExUnit — The Test Framework

ExUnit is Elixir's built-in test framework. If you know pytest, Jest, or JUnit, the structure is familiar.

```elixir
defmodule Kalcifer.FlowsTest do
  # DataCase sets up DB sandbox, imports helpers
  use Kalcifer.DataCase

  alias Kalcifer.Flows
  alias Kalcifer.Flows.Flow

  describe "create_flow/2" do
    test "creates a flow with valid attributes" do
      tenant = insert(:tenant)
      attrs = %{name: "Welcome Flow", description: "Onboarding"}

      assert {:ok, %Flow{} = flow} = Flows.create_flow(tenant, attrs)
      assert flow.name == "Welcome Flow"
      assert flow.status == "draft"
      assert flow.tenant_id == tenant.id
    end

    test "returns error with invalid attributes" do
      tenant = insert(:tenant)
      assert {:error, changeset} = Flows.create_flow(tenant, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end
end
```

**Running tests in Kalcifer:**
```bash
mix test --trace                    # ALWAYS use --trace (shows test names)
mix test test/kalcifer/flows_test.exs  # Single file
mix test test/kalcifer/flows_test.exs:15  # Single test by line number
```

**Underwater Rock**: Always use `--trace`. Without it, test output is minimal and you can't see which test is running. The CLAUDE.md mandates this.

### Test Setup and Tags

```elixir
defmodule Kalcifer.Engine.FlowServerTest do
  use Kalcifer.DataCase

  # Setup runs before each test in this module
  setup do
    tenant = insert(:tenant)
    flow = insert(:flow, tenant: tenant, status: "active")
    version = insert(:flow_version, flow: flow, status: "active",
      graph: simple_graph())

    {:ok, tenant: tenant, flow: flow, version: version}
  end

  # Tests receive setup context via pattern matching
  test "starts execution from entry node", %{version: version} do
    {:ok, instance} = Engine.start_instance(version, %{customer_id: "cust_1"})
    assert instance.status == "running"
  end

  # Tags for conditional setup
  @tag :slow
  test "handles 1000 concurrent instances" do
    # ...
  end
end

# Run only tagged tests:
# mix test --only slow
# Exclude tagged tests:
# mix test --exclude slow
```

### Async Tests

```elixir
# Async: true runs this module's tests concurrently with other modules
use Kalcifer.DataCase, async: true

# BUT: async tests can't share DB state between processes
# Kalcifer uses Ecto.Adapters.SQL.Sandbox for isolation
```

**Underwater Rock**: Async tests with GenServers require special care. The GenServer runs in a different process than the test. You must explicitly share the DB sandbox connection:

```elixir
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Kalcifer.Repo)
  Ecto.Adapters.SQL.Sandbox.mode(Kalcifer.Repo, {:shared, self()})
  # Now GenServers started during this test can access the DB
end
```

## ExMachina — Test Factories

ExMachina generates test data. It's like FactoryBot (Ruby) or factory_boy (Python).

```elixir
defmodule Kalcifer.Factory do
  use ExMachina.Ecto, repo: Kalcifer.Repo

  def tenant_factory do
    raw_key = "test_key_#{System.unique_integer()}"
    %Kalcifer.Tenants.Tenant{
      name: "Test Tenant",
      api_key_hash: :crypto.hash(:sha256, raw_key) |> Base.encode16(case: :lower),
      raw_api_key: raw_key  # Virtual field for test convenience
    }
  end

  def flow_factory do
    %Kalcifer.Flows.Flow{
      name: sequence(:flow_name, &"Flow #{&1}"),
      status: "draft",
      description: "Test flow",
      tenant: build(:tenant)
    }
  end

  def flow_version_factory do
    %Kalcifer.Flows.FlowVersion{
      version_number: 1,
      status: "draft",
      graph: %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"from" => "entry_1", "to" => "exit_1"}
        ]
      },
      flow: build(:flow)
    }
  end

  def flow_instance_factory do
    %Kalcifer.Flows.FlowInstance{
      status: "running",
      context: %{"_customer_id" => "test_customer"},
      flow: build(:flow),
      flow_version: build(:flow_version)
    }
  end

  def execution_step_factory do
    %Kalcifer.Flows.ExecutionStep{
      node_id: "node_1",
      node_type: "send_email",
      status: "completed",
      result: %{},
      flow_instance: build(:flow_instance)
    }
  end
end
```

### Usage in Tests

```elixir
# insert/1 — creates and inserts into DB
tenant = insert(:tenant)

# insert/2 — with overrides
flow = insert(:flow, tenant: tenant, status: "active", name: "Custom Name")

# build/1 — creates struct without inserting (for unit tests)
flow = build(:flow)

# build_pair/build_list — multiple records
flows = insert_list(5, :flow, tenant: tenant)

# Nested associations are auto-created
instance = insert(:flow_instance)
# This also created a flow, flow_version, and tenant
```

**Underwater Rock**: `insert/2` uses `build/2` internally and then inserts. Associations defined with `build(:assoc)` in the factory are auto-inserted. If you need to reuse a tenant across multiple flows, pass it explicitly:

```elixir
tenant = insert(:tenant)
flow1 = insert(:flow, tenant: tenant)  # Uses existing tenant
flow2 = insert(:flow, tenant: tenant)  # Same tenant
# WITHOUT passing tenant, each flow would create its own tenant
```

## Mox — Behaviour-Based Mocking

Mox creates mock modules that implement behaviours. It's NOT monkey-patching — it's dependency injection via Elixir's module system.

### Setup

```elixir
# In test/support/mocks.ex
Mox.defmock(Kalcifer.MockChannelProvider, for: Kalcifer.Channels.ProviderBehaviour)
Mox.defmock(Kalcifer.MockAIClient, for: Kalcifer.AI.ClientBehaviour)

# In config/test.exs
config :kalcifer, :channel_provider, Kalcifer.MockChannelProvider
config :kalcifer, :ai_client, Kalcifer.MockAIClient

# In production code — inject via config
defmodule Kalcifer.Channels.Sender do
  @provider Application.compile_env(:kalcifer, :channel_provider, Kalcifer.Channels.DefaultProvider)

  def send_message(channel, message) do
    @provider.deliver(channel, message)
  end
end
```

### Usage in Tests

```elixir
import Mox

test "sends email through provider" do
  instance = insert(:flow_instance)

  # Set expectation: the mock will be called exactly once with these args
  expect(Kalcifer.MockChannelProvider, :deliver, fn :email, message ->
    assert message.to == "user@example.com"
    {:ok, %{message_id: "msg_123"}}
  end)

  # Execute the code that should trigger the mock
  assert {:ok, _} = ChannelSender.send_message(:email, %{to: "user@example.com", body: "Hello"})

  # verify_on_exit! ensures all expectations were met (set up in setup block)
end

setup :verify_on_exit!  # Add this to ensure all mocks were called
```

### Stubs vs Expects

```elixir
# expect — must be called exactly N times (default 1)
expect(MockProvider, :deliver, 3, fn _, _ -> {:ok, %{}} end)

# stub — can be called any number of times (0 or more)
stub(MockProvider, :deliver, fn _, _ -> {:ok, %{}} end)

# Use expect when you NEED to verify the call happened
# Use stub when you just need the dependency to not crash
```

**Underwater Rock**: Mox expectations are per-process. In async tests, if a GenServer calls the mock, the expectation must be set with `allow/3`:

```elixir
test "GenServer calls provider" do
  {:ok, pid} = start_server()

  expect(MockProvider, :deliver, fn _, _ -> {:ok, %{}} end)
  |> allow(self(), pid)  # Allow the GenServer process to use this expectation

  GenServer.cast(pid, :send_message)
end
```

## StreamData — Property-Based Testing

Property-based testing generates hundreds of random inputs to find edge cases you'd never think of. It's like QuickCheck for Elixir.

```elixir
use ExUnitProperties

property "duration parser handles all valid formats" do
  check all hours <- integer(0..999),
            minutes <- integer(0..59) do
    input = "#{hours}h#{minutes}m"
    assert {:ok, seconds} = Duration.parse(input)
    assert seconds == hours * 3600 + minutes * 60
  end
end

property "graph walker never visits the same node twice" do
  check all graph <- graph_generator(),
            max_runs: 200 do
    visited = GraphWalker.traverse(graph)
    assert length(visited) == length(Enum.uniq(visited))
  end
end

# Custom generator for graphs
defp graph_generator do
  gen all node_count <- integer(2..20),
          nodes <- list_of(node_generator(), length: node_count),
          edges <- list_of(edge_generator(nodes), max_length: node_count * 2) do
    %{"nodes" => nodes, "edges" => Enum.uniq(edges)}
  end
end
```

**When to use property tests in Kalcifer:**
- Graph traversal algorithms (cycle detection, path finding)
- Duration parsing ("3d2h15m" → seconds)
- Context merging (verify associativity, commutativity)
- Node validation (config schema checking)

**Underwater Rock**: Property tests are slow (hundreds of iterations). Tag them and exclude from quick test runs:

```elixir
@tag :property
property "..." do
  # ...
end

# Run without property tests: mix test --exclude property
# Run only property tests: mix test --only property
```

## Testing Patterns Specific to Kalcifer

### Testing GenServer (FlowServer)

```elixir
test "FlowServer executes graph and reaches exit", %{version: version} do
  # Start FlowServer manually
  {:ok, pid} = FlowServer.start_link(
    instance_id: instance.id,
    graph: version.graph,
    context: %{"_customer_id" => "cust_1"}
  )

  # Wait for async execution to complete
  # Pattern: use Process.monitor + receive
  ref = Process.monitor(pid)

  receive do
    {:DOWN, ^ref, :process, ^pid, :normal} ->
      # Process terminated normally — flow completed
      instance = Repo.get!(FlowInstance, instance.id)
      assert instance.status == "completed"
  after
    5_000 -> flunk("FlowServer didn't complete in time")
  end
end
```

### Testing Oban Jobs

```elixir
use Oban.Testing, repo: Kalcifer.Repo

test "wait node schedules resume job" do
  # Trigger a flow with a wait node
  {:ok, instance} = Engine.trigger_flow(tenant.id, flow.id, "cust_1", %{})

  # Assert the Oban job was enqueued
  assert_enqueued(
    worker: ResumeFlowJob,
    args: %{"instance_id" => instance.id},
    queue: "delayed_resume"
  )
end

test "resume job restarts flow execution" do
  instance = insert(:flow_instance, status: "waiting",
    context: %{"_waiting_node_id" => "wait_1"})

  # Execute the job directly (not through the queue)
  assert :ok = perform_job(ResumeFlowJob, %{
    "instance_id" => instance.id,
    "node_id" => "wait_1"
  })

  updated = Repo.get!(FlowInstance, instance.id)
  assert updated.status in ["running", "completed"]
end
```

### Testing ETS-Dependent Code

```elixir
test "NodeRegistry looks up built-in nodes" do
  # NodeRegistry is started by the Engine.Supervisor
  # In tests, it's already running (started in test_helper.exs)

  assert {:ok, module} = NodeRegistry.lookup("send_email")
  assert module == Kalcifer.Engine.Nodes.Action.Channel.SendEmail

  # IMPORTANT: Use >= assertions for count, not ==
  # because other tests may have added entries
  count = NodeRegistry.count()
  assert count >= 23  # At least 23 built-in nodes
end
```

### Testing with FlowServer Resume (Direct Cast)

```elixir
# From CLAUDE.md: For FlowServer resume tests, use direct GenServer.cast
# instead of relying on Oban inline mode

test "FlowServer resumes from wait node" do
  # Create instance in waiting state
  instance = insert(:flow_instance, status: "waiting",
    context: %{"_waiting_node_id" => "wait_1"})

  # Start the FlowServer
  {:ok, pid} = FlowServer.start_link(instance_id: instance.id)

  # Resume directly via GenServer cast (not through Oban)
  GenServer.cast(pid, {:resume, "wait_1", %{event: "clicked"}})

  # Wait for processing
  :timer.sleep(100)  # Or use Process.monitor pattern

  state = FlowServer.get_state(instance.id)
  assert state.current_node != "wait_1"
end
```

## Test Organization

```
test/
├── test_helper.exs              # Setup: start Oban, configure sandbox
├── support/
│   ├── factory.ex               # ExMachina factories
│   ├── data_case.ex             # DB test case template
│   ├── conn_case.ex             # HTTP test case template
│   └── mocks.ex                 # Mox mock definitions
├── kalcifer/
│   ├── flows_test.exs           # Context tests
│   ├── engine/
│   │   ├── flow_server_test.exs # GenServer tests
│   │   ├── graph_walker_test.exs
│   │   ├── node_registry_test.exs
│   │   └── nodes/               # Per-node tests
│   └── marketing/
│       └── journey_test.exs
├── kalcifer_web/
│   └── controllers/
│       ├── flow_controller_test.exs
│       └── trigger_controller_test.exs
```

## Common Test Mistakes

1. **Not sharing sandbox in async tests with GenServers**: GenServer processes can't see the test's DB transaction without explicit `Sandbox.mode({:shared, self()})`.

2. **Using `== N` for ETS counts**: Other test modules may have added ETS entries. Always use `>= N`.

3. **Relying on Oban inline for FlowServer tests**: Inline mode processes jobs in the same process, which can deadlock with GenServer calls. Use direct `GenServer.cast` instead.

4. **Not cleaning up GenServer processes**: If a test starts a FlowServer but doesn't stop it, it lingers and can interfere with other tests. Use `on_exit/1`:

```elixir
setup do
  {:ok, pid} = FlowServer.start_link(instance_id: id)
  on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  {:ok, pid: pid}
end
```

5. **Forgetting `verify_on_exit!` with Mox**: Without this, unmet mock expectations silently pass.

## Recommended Resources

- ExUnit docs: hexdocs.pm/ex_unit
- ExMachina: github.com/thoughtbot/ex_machina
- Mox: hexdocs.pm/mox (José Valim's blog post on Mox is essential reading)
- StreamData: hexdocs.pm/stream_data
- "Testing Elixir" by Andrea Leopardi and Jeffrey Matthias (the definitive book)
