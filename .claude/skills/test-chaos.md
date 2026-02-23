# /test-chaos — Write chaos/failure tests

Test system resilience: process crashes, DB failures, race conditions, recovery.
The user describes the failure scenario to test.

## Steps

### 1. Identify failure modes

For Kalcifer, key chaos scenarios:

**Process failures**:
- FlowServer crashes mid-execution
- FlowServer crashes while waiting
- NodeRegistry crashes and restarts
- EventRouter crashes while dispatching
- DynamicSupervisor restart behavior

**DB failures**:
- DB connection lost during persistence
- Unique constraint violations (concurrent inserts)
- Transaction timeouts

**Timing/race conditions**:
- Event arrives before FlowServer is fully initialized
- Event arrives after FlowServer has already completed
- Two events arriving simultaneously for same wait node
- Trigger while another trigger for same customer is in progress

**Recovery scenarios**:
- RecoveryManager restores running instances after restart
- RecoveryManager restores waiting instances and re-registers events
- Partial recovery (some instances fail to restore)

### 2. Create test file

File: `test/chaos/{scenario_name}_test.exs`

```elixir
defmodule Kalcifer.Chaos.{ScenarioName}Test do
  @moduledoc """
  Chaos test: {describe the failure scenario}
  """
  use Kalcifer.DataCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Engine.FlowServer

  describe "FlowServer crash recovery" do
    test "instance is recoverable after FlowServer crash" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant, status: "active")
      insert(:flow_version, flow: flow, version_number: 1, status: "published")

      instance = insert(:flow_instance,
        flow: flow,
        tenant: tenant,
        status: "waiting",
        current_nodes: ["wait_1"],
        context: %{"accumulated" => %{}}
      )

      # Start FlowServer
      {:ok, pid} = start_flow_server(instance)
      ref = Process.monitor(pid)

      # Kill it abruptly
      Process.exit(pid, :kill)

      receive do
        {:DOWN, ^ref, :process, ^pid, :killed} -> :ok
      after
        1000 -> flunk("Process didn't die")
      end

      # Verify instance is still in DB with waiting status
      reloaded = Kalcifer.Repo.get!(Kalcifer.Flows.FlowInstance, instance.id)
      assert reloaded.status == "waiting"

      # Recovery should be able to restart it
      # (RecoveryManager.recover/0 or manual restart)
    end
  end

  describe "concurrent event handling" do
    test "two simultaneous events for same customer don't cause crashes" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant, status: "active")
      insert(:flow_version, flow: flow, version_number: 1, status: "published")

      instance = insert(:flow_instance,
        flow: flow,
        tenant: tenant,
        customer_id: "chaos_cust_1",
        status: "waiting",
        current_nodes: ["wait_1"]
      )

      {:ok, pid} = start_flow_server(instance)

      # Fire two events concurrently
      via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance.id}}

      tasks = for i <- 1..5 do
        Task.async(fn ->
          GenServer.cast(via, {:resume, "wait_1", :event_received})
        end)
      end

      Task.await_many(tasks)
      Process.sleep(300)

      # Process should still be alive OR have completed normally
      case GenServer.whereis(via) do
        nil ->
          # Completed — verify DB state
          reloaded = Kalcifer.Repo.get!(Kalcifer.Flows.FlowInstance, instance.id)
          assert reloaded.status in ["completed", "waiting"]

        _pid ->
          # Still alive — that's fine too
          :ok
      end
    end
  end

  describe "DB failure during persistence" do
    test "FlowServer handles Repo errors gracefully" do
      # Use Ecto.Sandbox to simulate failures
      # or test with invalid data that triggers constraint violations
    end
  end

  # Helper to start a FlowServer with test state
  defp start_flow_server(instance) do
    # Implementation depends on FlowServer.start_link/1 signature
    # Read the actual FlowServer module to determine correct args
  end
end
```

### 3. Chaos test patterns

**Kill and verify**:
```elixir
pid = GenServer.whereis(via)
ref = Process.monitor(pid)
Process.exit(pid, :kill)
receive do
  {:DOWN, ^ref, :process, ^pid, :killed} -> :ok
after
  1000 -> flunk("Process didn't die")
end
```

**Concurrent stress**:
```elixir
tasks = for _ <- 1..50 do
  Task.async(fn ->
    # Perform concurrent operation
  end)
end
results = Task.await_many(tasks, 5000)
```

**Supervisor restart verification**:
```elixir
# Get initial pid
pid1 = GenServer.whereis(name)
Process.exit(pid1, :kill)
Process.sleep(100)
# Verify supervisor restarted it
pid2 = GenServer.whereis(name)
assert pid2 != nil
assert pid2 != pid1
```

### 4. Conventions

- Always `async: false` — chaos tests affect shared state
- Use `Process.sleep/1` conservatively (prefer monitors)
- Clean up: ensure killed processes don't leak
- Test BOTH the failure AND the recovery
- Document what failure is being simulated in test name
- Place in `test/chaos/` directory

### 5. Verify

```bash
mix test --trace test/chaos/{scenario_name}_test.exs
```
