# Kalcifer — Testing & Reliability Strategy

**Version**: 1.0
**Date**: 2026-02-22
**Status**: Draft

---

## 1. Philosophy

> "In a world where AI writes code, the competitive advantage shifts to quality, resilience, scalability, performance, lightness, and readiness."

Kalcifer's testing strategy is not a development aid — it is a **product feature**. Every release publishes a public **Reliability Report** with concrete numbers: how many scenarios were tested, how the system behaved under chaos, what throughput it sustained. This transparency is our moat.

### Testing Pyramid (Inverted Priorities)

Traditional pyramid: many unit tests, few integration tests, fewer E2E.

**Kalcifer pyramid**: unit tests are table stakes. The real value is in property-based tests, chaos tests, and load tests — because a customer journey engine's correctness cannot be proven by unit tests alone.

```
┌─────────────────────────────┐
│     Load & Stress Tests     │  ← "Can it handle 100K concurrent journeys?"
├─────────────────────────────┤
│       Chaos Tests           │  ← "What happens when things break?"
├─────────────────────────────┤
│   Property-Based Tests      │  ← "Does it ALWAYS work, not just for my examples?"
├─────────────────────────────┤
│   Integration Tests         │  ← "Do components work together?"
├─────────────────────────────┤
│       Unit Tests            │  ← "Does each piece work in isolation?"
└─────────────────────────────┘
```

---

## 2. Test Categories

### 2.1 Unit Tests

**Scope**: Individual modules, pure functions, node logic.
**Framework**: ExUnit (standard)
**Coverage Target**: > 90% line coverage

```elixir
# test/optio_flow/engine/nodes/logic/ab_split_test.exs
defmodule Kalcifer.Engine.Nodes.Logic.ABSplitTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Logic.ABSplit

  describe "execute/2" do
    test "assigns variant deterministically based on customer_id" do
      config = %{"variants" => [
        %{"key" => "A", "weight" => 50},
        %{"key" => "B", "weight" => 50}
      ]}

      context1 = %{customer_id: "customer_1", journey_id: "j1"}
      context2 = %{customer_id: "customer_1", journey_id: "j1"}

      # Same customer + journey = same variant (deterministic)
      assert ABSplit.execute(config, context1) == ABSplit.execute(config, context2)
    end

    test "distributes roughly according to weights over many customers" do
      config = %{"variants" => [
        %{"key" => "A", "weight" => 70},
        %{"key" => "B", "weight" => 30}
      ]}

      results =
        1..10_000
        |> Enum.map(fn i ->
          context = %{customer_id: "c#{i}", journey_id: "j1"}
          {:branched, variant, _} = ABSplit.execute(config, context)
          variant
        end)
        |> Enum.frequencies()

      # With 10K samples, should be within ~5% of expected distribution
      a_ratio = results[:A] / 10_000
      assert_in_delta a_ratio, 0.70, 0.05
    end
  end

  describe "validate/1" do
    test "requires at least 2 variants" do
      assert {:error, _} = ABSplit.validate(%{"variants" => [%{"key" => "A", "weight" => 100}]})
    end

    test "accepts valid config" do
      config = %{"variants" => [
        %{"key" => "A", "weight" => 50},
        %{"key" => "B", "weight" => 50}
      ]}
      assert :ok = ABSplit.validate(config)
    end
  end
end
```

**What unit tests cover**:
- Node execution logic (all 20 nodes)
- Graph validation (cycles, orphans, branch completeness)
- Journey state transitions
- Template rendering
- Segment query building
- Config validation
- Duration parsing
- Frequency cap calculations

### 2.2 Integration Tests

**Scope**: Components interacting with real databases and each other.
**Framework**: ExUnit + Ecto.Adapters.SQL.Sandbox
**Databases**: PostgreSQL (real), Elasticsearch (real via Docker), ClickHouse (real via Docker)

```elixir
# test/optio_flow/engine/journey_server_integration_test.exs
defmodule Kalcifer.Engine.JourneyServerIntegrationTest do
  use Kalcifer.DataCase  # Ecto sandbox

  alias Kalcifer.Engine.{JourneyServer, EventRouter}

  describe "full journey execution" do
    test "executes entry → email → wait → goal journey" do
      # Setup
      journey = Factory.insert(:journey, graph: Fixtures.simple_email_journey())
      customer = Factory.insert(:customer, %{email: "test@example.com"})

      # Mock email provider
      expect(MockEmailProvider, :send, fn _to, _subject, _body, _opts ->
        {:ok, "msg_123"}
      end)

      # Start journey instance
      {:ok, pid} = JourneyServer.start_link(%{
        journey_id: journey.id,
        customer_id: customer.id,
        entry_node_id: "entry_1",
        tenant_id: journey.tenant_id
      })

      # Wait for email node to execute
      assert_receive {:node_executed, "email_1", :completed}, 1_000

      # Verify email was sent
      assert_received {:mock_email_sent, "test@example.com"}

      # Verify instance is now waiting at wait_for_event node
      state = JourneyServer.get_state(pid)
      assert state.state == :waiting
      assert "wait_1" in state.current_nodes

      # Simulate customer event
      EventRouter.dispatch(journey.tenant_id, customer.id, %{
        event_type: "email_opened",
        data: %{}
      })

      # Verify journey continued on "event_received" branch
      assert_receive {:node_executed, "goal_1", :completed}, 1_000

      # Verify instance completed
      state = JourneyServer.get_state(pid)
      assert state.state == :completed

      # Verify persistence
      instance = Repo.get!(JourneyInstance, state.instance_id)
      assert instance.status == :completed
      assert instance.completed_at != nil

      # Verify execution steps recorded
      steps = Repo.all(from s in ExecutionStep, where: s.instance_id == ^state.instance_id, order_by: s.started_at)
      assert length(steps) == 4  # entry, email, wait, goal
      assert Enum.map(steps, & &1.node_type) == ["event_entry", "send_email", "wait_for_event", "goal_reached"]
    end

    test "wait_for_event times out and takes timeout branch" do
      journey = Factory.insert(:journey, graph: Fixtures.wait_for_event_journey(timeout: "100ms"))
      customer = Factory.insert(:customer)

      {:ok, pid} = JourneyServer.start_link(%{
        journey_id: journey.id,
        customer_id: customer.id,
        entry_node_id: "entry_1",
        tenant_id: journey.tenant_id
      })

      # Don't send any event — let it timeout
      assert_receive {:node_executed, "timeout_email", :completed}, 2_000

      # Verify it took the timeout branch, not the event branch
      steps = get_execution_steps(pid)
      node_ids = Enum.map(steps, & &1.node_id)
      assert "timeout_email" in node_ids
      refute "engaged_email" in node_ids
    end
  end
end
```

**What integration tests cover**:
- Full journey execution (entry → nodes → exit)
- WaitForEvent with real event dispatch
- Timeout behavior
- Parallel branch execution
- Exit criteria triggering
- Frequency cap enforcement across journeys
- State persistence and recovery
- Analytics pipeline (PG → Broadway → ClickHouse)
- API endpoints with real database
- WebSocket channel updates
- Multi-tenancy isolation

### 2.3 Property-Based Tests

**Scope**: Invariants that must hold for ALL possible inputs.
**Framework**: StreamData
**Target**: > 500 unique property scenarios

This is where Kalcifer's testing becomes extraordinary.

```elixir
# test/property/journey_graph_test.exs
defmodule Kalcifer.Property.JourneyGraphTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Kalcifer.Journeys.JourneyGraph

  # Generator: random valid journey graph
  defp journey_graph_gen do
    gen all num_nodes <- integer(2..20),
            nodes <- list_of(node_gen(), length: num_nodes),
            edges <- valid_edges_gen(nodes) do
      %{"nodes" => nodes, "edges" => edges}
    end
  end

  # PROPERTY: Valid graphs always pass validation
  property "valid DAG graphs pass validation" do
    check all graph <- valid_dag_gen() do
      assert :ok = JourneyGraph.validate(graph)
    end
  end

  # PROPERTY: Graphs with cycles always fail validation
  property "graphs with cycles are always rejected" do
    check all graph <- graph_with_cycle_gen() do
      assert {:error, errors} = JourneyGraph.validate(graph)
      assert Enum.any?(errors, &String.contains?(&1, "cycle"))
    end
  end

  # PROPERTY: Adding an unreachable node always fails validation
  property "orphan nodes are always detected" do
    check all graph <- valid_dag_gen(),
              orphan <- node_gen() do
      graph_with_orphan = add_orphan_node(graph, orphan)
      assert {:error, errors} = JourneyGraph.validate(graph_with_orphan)
      assert Enum.any?(errors, &String.contains?(&1, "unreachable"))
    end
  end
end
```

```elixir
# test/property/state_machine_test.exs
defmodule Kalcifer.Property.StateMachineTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Kalcifer.Engine.JourneyState

  # Generator: random sequence of valid commands
  defp command_sequence_gen do
    gen all commands <- list_of(
      one_of([
        constant(:start),
        constant(:pause),
        constant(:resume),
        constant(:complete),
        constant(:fail),
        constant(:exit)
      ]),
      min_length: 1,
      max_length: 50
    ) do
      commands
    end
  end

  # PROPERTY: State machine never reaches an invalid state
  property "state machine always transitions to valid states" do
    check all commands <- command_sequence_gen() do
      state = JourneyState.initial()

      final_state =
        Enum.reduce(commands, state, fn command, acc ->
          case JourneyState.apply_command(acc, command) do
            {:ok, new_state} -> new_state
            {:error, :invalid_transition} -> acc  # Invalid commands are no-ops
          end
        end)

      assert final_state.status in JourneyState.valid_states()
    end
  end

  # PROPERTY: Terminal states are truly terminal
  property "completed/failed states cannot be transitioned from" do
    check all commands <- command_sequence_gen(),
              terminal <- one_of([constant(:completed), constant(:failed)]) do
      state = %JourneyState{status: terminal}

      for command <- commands do
        assert {:error, :invalid_transition} = JourneyState.apply_command(state, command)
      end
    end
  end

  # PROPERTY: Idempotent persistence — saving and loading state is identity
  property "persisted state roundtrips correctly" do
    check all state <- journey_state_gen() do
      serialized = JourneyState.serialize(state)
      deserialized = JourneyState.deserialize(serialized)
      assert state == deserialized
    end
  end
end
```

```elixir
# test/property/event_routing_test.exs
defmodule Kalcifer.Property.EventRoutingTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # PROPERTY: Every registered wait receives matching events
  property "registered waits always receive matching events" do
    check all customer_id <- string(:alphanumeric, min_length: 1),
              event_type <- string(:alphanumeric, min_length: 1),
              instance_id <- string(:alphanumeric, min_length: 1) do
      router = start_supervised!(EventRouter)

      EventRouter.register_wait(router, customer_id, event_type, instance_id, "node_1")

      :ok = EventRouter.dispatch(router, customer_id, %{event_type: event_type, data: %{}})

      assert_receive {:customer_event, %{event_type: ^event_type}}
    end
  end

  # PROPERTY: Events for unregistered customers are silently dropped
  property "events for non-waiting customers do not crash" do
    check all customer_id <- string(:alphanumeric, min_length: 1),
              event_type <- string(:alphanumeric, min_length: 1) do
      router = start_supervised!(EventRouter)

      # No registration — dispatch should be safe
      assert :ok = EventRouter.dispatch(router, customer_id, %{event_type: event_type, data: %{}})
    end
  end

  # PROPERTY: Unregistered waits don't receive events
  property "unregistered waits stop receiving events" do
    check all customer_id <- string(:alphanumeric, min_length: 1),
              event_type <- string(:alphanumeric, min_length: 1) do
      router = start_supervised!(EventRouter)

      EventRouter.register_wait(router, customer_id, event_type, "inst_1", "node_1")
      EventRouter.unregister_wait(router, customer_id, event_type, "inst_1", "node_1")

      EventRouter.dispatch(router, customer_id, %{event_type: event_type, data: %{}})

      refute_receive {:customer_event, _}, 100
    end
  end
end
```

```elixir
# test/property/frequency_cap_test.exs
defmodule Kalcifer.Property.FrequencyCapTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # PROPERTY: Frequency cap is NEVER exceeded
  property "frequency cap always enforced regardless of send pattern" do
    check all max_sends <- integer(1..10),
              window_seconds <- integer(1..60),
              send_attempts <- integer(1..100) do
      cap = %{max: max_sends, window_seconds: window_seconds}
      state = FrequencyCap.new(cap)

      {allowed, _state} =
        Enum.reduce(1..send_attempts, {0, state}, fn _, {count, s} ->
          now = DateTime.utc_now()
          case FrequencyCap.check_and_record(s, "c1", :email, now) do
            {:ok, new_s} -> {count + 1, new_s}
            {:exceeded, new_s} -> {count, new_s}
          end
        end)

      assert allowed <= max_sends
    end
  end
end
```

**Key Properties to Verify**:

| # | Property | Category |
|---|----------|----------|
| 1 | Valid DAGs always pass graph validation | Graph |
| 2 | Cyclic graphs always fail validation | Graph |
| 3 | Orphan nodes always detected | Graph |
| 4 | State machine never reaches invalid state | State Machine |
| 5 | Terminal states are truly terminal | State Machine |
| 6 | State serialization roundtrips perfectly | Persistence |
| 7 | Registered waits always receive matching events | Event Routing |
| 8 | Unregistered waits never receive events | Event Routing |
| 9 | Frequency cap is never exceeded | Business Logic |
| 10 | A/B split is deterministic per customer | Business Logic |
| 11 | A/B split distribution matches weights (statistical) | Business Logic |
| 12 | Deduplication prevents duplicate sends | Reliability |
| 13 | Journey exit criteria always checked at every step | Business Logic |
| 14 | Multi-tenant queries never leak data | Security |
| 15 | Concurrent event dispatch doesn't lose events | Concurrency |
| 16 | Version migration preserves customer position (mapped nodes) | Versioning |
| 17 | Version migration never creates orphan instances (unmapped = handled) | Versioning |
| 18 | Rollback + re-migrate is idempotent (no state corruption) | Versioning |
| 19 | Gradual rollout respects configured percentage (±5%) | Versioning |
| 20 | AI-generated graphs always pass validation | AI Designer |
| 21 | Node mapping is complete (every old node mapped or explicitly marked removed) | Versioning |
| 22 | Concurrent migration + new entry doesn't lose customers | Versioning |
| 23 | Migration of waiting instances re-registers event listeners correctly | Versioning |

### 2.4 Chaos Tests

**Scope**: System behavior when things go wrong.
**Framework**: ExUnit + process manipulation + network simulation
**Frequency**: Weekly in CI + every pre-release

```elixir
# test/chaos/process_kill_test.exs
defmodule Kalcifer.Chaos.ProcessKillTest do
  use Kalcifer.DataCase

  describe "JourneyServer crash recovery" do
    test "journey resumes after JourneyServer process is killed" do
      # Start a journey that reaches WaitForEvent
      {:ok, pid} = start_journey_until_waiting()
      instance_id = JourneyServer.get_state(pid).instance_id

      # Verify it's waiting
      assert Process.alive?(pid)
      state_before = JourneyServer.get_state(pid)
      assert state_before.state == :waiting

      # KILL the process (simulate crash)
      Process.exit(pid, :kill)
      refute Process.alive?(pid)

      # Wait for supervisor to notice and RecoveryManager to act
      Process.sleep(500)

      # Verify instance was recovered
      recovered_pid = JourneyServer.whereis(instance_id)
      assert recovered_pid != nil
      assert recovered_pid != pid  # New process

      recovered_state = JourneyServer.get_state(recovered_pid)
      assert recovered_state.state == :waiting
      assert recovered_state.current_nodes == state_before.current_nodes

      # Send the event — recovered instance should handle it
      EventRouter.dispatch(
        state_before.tenant_id,
        state_before.customer_id,
        %{event_type: "email_opened", data: %{}}
      )

      assert_receive {:node_executed, "goal_1", :completed}, 2_000
    end

    test "mass process kill — 1000 journeys recover" do
      # Start 1000 journey instances
      instances = Enum.map(1..1000, fn i ->
        {:ok, pid} = start_journey_until_waiting(customer_id: "c#{i}")
        {pid, JourneyServer.get_state(pid).instance_id}
      end)

      # Kill ALL of them simultaneously
      Enum.each(instances, fn {pid, _} ->
        Process.exit(pid, :kill)
      end)

      # Wait for recovery
      Process.sleep(5_000)

      # Verify ALL recovered
      recovered = Enum.count(instances, fn {_, instance_id} ->
        JourneyServer.whereis(instance_id) != nil
      end)

      assert recovered == 1000
    end

    test "rapid kill-restart cycle doesn't corrupt state" do
      {:ok, pid} = start_journey_until_waiting()
      instance_id = JourneyServer.get_state(pid).instance_id

      # Kill and let recover 10 times rapidly
      for _ <- 1..10 do
        current_pid = JourneyServer.whereis(instance_id)
        if current_pid, do: Process.exit(current_pid, :kill)
        Process.sleep(200)
      end

      Process.sleep(2_000)

      # State should still be consistent
      final_pid = JourneyServer.whereis(instance_id)
      assert final_pid != nil
      state = JourneyServer.get_state(final_pid)
      assert state.state in [:waiting, :running]

      # Database should be consistent with process state
      db_instance = Repo.get!(JourneyInstance, instance_id)
      assert db_instance.status == state.state
    end
  end
end
```

```elixir
# test/chaos/db_disconnect_test.exs
defmodule Kalcifer.Chaos.DbDisconnectTest do
  use Kalcifer.DataCase

  describe "PostgreSQL disconnect" do
    test "journey execution pauses during DB outage and resumes after" do
      {:ok, pid} = start_journey_at_node("email_1")

      # Simulate DB disconnect by checking out all connections
      exhaust_db_pool()

      # Try to execute — should queue, not crash
      send(pid, {:execute_node, "email_1"})
      Process.sleep(500)
      assert Process.alive?(pid)  # Process didn't crash

      # Restore DB connections
      restore_db_pool()

      # Node should eventually execute
      assert_receive {:node_executed, "email_1", :completed}, 10_000
    end

    test "analytics pipeline handles ClickHouse unavailability gracefully" do
      # Generate execution events
      generate_execution_events(100)

      # Make ClickHouse unavailable
      stop_clickhouse_container()

      # Broadway should buffer, not crash
      Process.sleep(2_000)
      assert Process.alive?(Process.whereis(Kalcifer.Analytics.Pipeline))

      # Restart ClickHouse
      start_clickhouse_container()

      # Events should eventually arrive
      Process.sleep(10_000)
      assert clickhouse_event_count() >= 100
    end
  end
end
```

```elixir
# test/chaos/concurrent_stress_test.exs
defmodule Kalcifer.Chaos.ConcurrentStressTest do
  use Kalcifer.DataCase

  describe "concurrent operations" do
    test "same customer entering same journey twice is handled correctly" do
      journey = Factory.insert(:journey, graph: Fixtures.simple_journey())

      # Two concurrent entry attempts for same customer
      tasks = for _ <- 1..2 do
        Task.async(fn ->
          JourneyServer.start_link(%{
            journey_id: journey.id,
            customer_id: "same_customer",
            entry_node_id: "entry_1",
            tenant_id: journey.tenant_id
          })
        end)
      end

      results = Task.await_many(tasks)

      # Exactly one should succeed (deduplication)
      ok_count = Enum.count(results, &match?({:ok, _}, &1))
      assert ok_count == 1
    end

    test "100 events dispatched simultaneously for same customer" do
      {:ok, _pid} = start_journey_until_waiting(
        customer_id: "c1",
        waiting_for: "purchase"
      )

      # Dispatch 100 events concurrently
      tasks = for i <- 1..100 do
        Task.async(fn ->
          EventRouter.dispatch("tenant_1", "c1", %{
            event_type: "purchase",
            data: %{order_id: "order_#{i}"}
          })
        end)
      end

      Task.await_many(tasks)
      Process.sleep(1_000)

      # Journey should have continued exactly once (first event wins)
      steps = get_execution_steps_for_customer("c1")
      goal_steps = Enum.filter(steps, &(&1.node_type == "goal_reached"))
      assert length(goal_steps) == 1
    end
  end
end
```

**Chaos Scenarios**:

| # | Scenario | Expectation |
|---|----------|-------------|
| 1 | Kill single JourneyServer process | Recovers from DB within 5s |
| 2 | Kill 1000 JourneyServer processes simultaneously | All recover within 30s |
| 3 | Rapid kill-restart cycle (10x) | State remains consistent |
| 4 | PostgreSQL connection pool exhausted | Execution queues, doesn't crash |
| 5 | PostgreSQL goes down for 30s | Buffered operations complete after reconnect |
| 6 | ClickHouse unavailable | Analytics buffers, engine unaffected |
| 7 | Elasticsearch unavailable | Segment evaluation fails gracefully, non-segment nodes continue |
| 8 | EventRouter process crash | Supervisor restarts, waits re-register from DB |
| 9 | OTP node restart | All running instances recovered from DB |
| 10 | Duplicate event dispatch (100x same event) | Journey continues exactly once |
| 11 | Same customer enters same journey concurrently | Exactly one instance created |
| 12 | Memory pressure (10M processes) | Graceful degradation with backpressure |
| 13 | Migration mid-flight + process crash | Instance recovers on correct version |
| 14 | Migration + simultaneous new entries | New entries use latest version, migration continues |
| 15 | Rollback during active migration | Migration aborts, instances return to previous version |
| 16 | LLM provider timeout during AI design | Graceful error, conversation state preserved |
| 17 | Migration of 50K instances with 10% node removal | Removed-node policy applied correctly to all |

### 2.5 Load Tests

**Scope**: Performance and scalability under realistic load.
**Frequency**: Weekly in CI + every pre-release
**Reports**: Published with each release

```elixir
# test/load/concurrent_journeys_test.exs
defmodule Kalcifer.Load.ConcurrentJourneysTest do
  use Kalcifer.DataCase, async: false

  @tag :load
  @tag timeout: 300_000  # 5 minutes

  describe "concurrent journey capacity" do
    test "sustain 100K concurrent journey instances" do
      journey = Factory.insert(:journey, graph: Fixtures.wait_journey())

      # Start instances in batches of 1000
      started = for batch <- 1..100 do
        tasks = for i <- 1..1000 do
          customer_id = "c_#{batch}_#{i}"
          Task.async(fn ->
            JourneyServer.start_link(%{
              journey_id: journey.id,
              customer_id: customer_id,
              entry_node_id: "entry_1",
              tenant_id: "load_test"
            })
          end)
        end

        results = Task.await_many(tasks, 30_000)
        ok_count = Enum.count(results, &match?({:ok, _}, &1))
        ok_count
      end

      total = Enum.sum(started)
      assert total == 100_000

      # Measure memory
      memory = :erlang.memory(:total)
      memory_mb = memory / 1_024 / 1_024
      IO.puts("Memory for 100K instances: #{Float.round(memory_mb, 1)} MB")
      assert memory_mb < 2_000  # Must be under 2GB

      # Measure event dispatch latency with all instances alive
      latencies = for _ <- 1..1000 do
        customer_id = "c_#{:rand.uniform(100)}_#{:rand.uniform(1000)}"
        start = System.monotonic_time(:microsecond)
        EventRouter.dispatch("load_test", customer_id, %{event_type: "test", data: %{}})
        System.monotonic_time(:microsecond) - start
      end

      p50 = percentile(latencies, 50)
      p99 = percentile(latencies, 99)
      IO.puts("Event dispatch latency — p50: #{p50}μs, p99: #{p99}μs")
      assert p99 < 50_000  # p99 under 50ms
    end
  end

  describe "event throughput" do
    test "sustain 10K events/second" do
      # Start 10K journey instances waiting for events
      start_waiting_instances(10_000)

      # Fire 10K events in 1 second
      start_time = System.monotonic_time(:millisecond)

      tasks = for i <- 1..10_000 do
        Task.async(fn ->
          EventRouter.dispatch("load_test", "c_#{i}", %{
            event_type: "purchase",
            data: %{order_id: i}
          })
        end)
      end

      Task.await_many(tasks, 30_000)
      elapsed = System.monotonic_time(:millisecond) - start_time

      throughput = 10_000 / (elapsed / 1000)
      IO.puts("Event throughput: #{Float.round(throughput, 0)} events/sec (elapsed: #{elapsed}ms)")
      assert throughput >= 10_000
    end
  end
end
```

**Load Test Metrics Published per Release**:

| Metric | Measurement | Target |
|--------|-------------|--------|
| Max concurrent instances | Count | > 100,000 |
| Memory per 100K instances | MB | < 2,000 |
| Event dispatch latency (p50) | μs | < 5,000 |
| Event dispatch latency (p99) | μs | < 50,000 |
| Events/second sustained | Count/s | > 10,000 |
| Journey start latency (p99) | ms | < 200 |
| Node execution latency (p99) | ms | < 50 |
| Crash recovery time (1000 instances) | seconds | < 30 |
| Zero-downtime deploy verified | boolean | true |

---

## 3. CI Pipeline

### 3.1 On Every Pull Request

```yaml
# .github/workflows/ci.yml
name: CI
on: [pull_request]

jobs:
  quality:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
      elasticsearch:
        image: elasticsearch:8.15.0
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.17'
          otp-version: '27'

      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix format --check-formatted
      - run: mix credo --strict
      - run: mix dialyzer
      - run: mix test --cover
      - run: mix test test/property --include property    # Property tests

      # Coverage gate
      - name: Check coverage
        run: |
          mix coveralls.json
          # Fail if under 90%
```

### 3.2 Weekly + Pre-release

```yaml
# .github/workflows/chaos-test.yml
name: Chaos & Load Tests
on:
  schedule:
    - cron: '0 3 * * 0'  # Weekly Sunday 3am
  workflow_dispatch:        # Manual trigger for releases

jobs:
  chaos:
    runs-on: ubuntu-latest-16-core  # Larger runner for load tests
    services:
      postgres:
        image: postgres:16
      elasticsearch:
        image: elasticsearch:8.15.0
      clickhouse:
        image: clickhouse/clickhouse-server:24-alpine
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1

      - run: mix deps.get
      - run: mix test test/chaos --include chaos
      - run: mix test test/load --include load

      # Generate reliability report
      - name: Generate Reliability Report
        run: mix optio_flow.reliability_report

      # Publish as GitHub release asset
      - name: Upload Report
        uses: actions/upload-artifact@v4
        with:
          name: reliability-report
          path: reports/reliability-report.md
```

### 3.3 Reliability Report Format

Every release includes a markdown report:

```markdown
# Kalcifer v0.3.0 — Reliability Report

**Date**: 2026-04-15
**Environment**: Ubuntu 22.04, 16 cores, 32GB RAM
**Duration**: 47 minutes

## Test Summary
| Category | Passed | Failed | Skipped |
|----------|--------|--------|---------|
| Unit Tests | 342 | 0 | 0 |
| Integration Tests | 87 | 0 | 0 |
| Property-Based | 523 scenarios | 0 | 0 |
| Chaos Tests | 12 | 0 | 0 |
| Load Tests | 6 | 0 | 0 |

## Performance Results
| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Max concurrent instances | 127,340 | 100,000 | PASS |
| Memory @ 100K instances | 1,247 MB | 2,000 MB | PASS |
| Event throughput | 14,230/s | 10,000/s | PASS |
| Event latency p99 | 31ms | 50ms | PASS |
| Crash recovery (1000) | 4.2s | 30s | PASS |

## Chaos Test Results
| Scenario | Result | Recovery Time |
|----------|--------|---------------|
| Single process kill | RECOVERED | 0.3s |
| Mass kill (1000) | ALL RECOVERED | 4.2s |
| DB disconnect 30s | SURVIVED | immediate |
| ClickHouse down | ENGINE UNAFFECTED | - |
| Rapid kill cycle (10x) | STATE CONSISTENT | - |

## Coverage
- Line coverage: 94.2%
- Branch coverage: 87.1%
- Property scenarios explored: 523
```

---

## 4. Testing Infrastructure

### 4.1 Test Helpers & Factories

```elixir
# test/support/factory.ex
defmodule Kalcifer.Factory do
  use ExMachina.Ecto, repo: Kalcifer.Repo

  def journey_factory do
    %Kalcifer.Journeys.Journey{
      tenant_id: "test_tenant",
      name: sequence(:name, &"Journey #{&1}"),
      status: :draft,
      graph: Fixtures.simple_journey()
    }
  end

  def customer_factory do
    %{
      id: sequence(:customer_id, &"customer_#{&1}"),
      email: sequence(:email, &"user#{&1}@test.com"),
      attributes: %{}
    }
  end
end
```

### 4.2 Mock Channel Providers

```elixir
# test/support/channel_mock.ex
Mox.defmock(MockEmailProvider, for: Kalcifer.Channels.EmailProvider)
Mox.defmock(MockSmsProvider, for: Kalcifer.Channels.SmsProvider)
Mox.defmock(MockPushProvider, for: Kalcifer.Channels.PushProvider)
Mox.defmock(MockProfileStore, for: Kalcifer.Customers.ProfileStore)

# In test config:
config :optio_flow, :email_provider, MockEmailProvider
config :optio_flow, :sms_provider, MockSmsProvider
```

### 4.3 Performance Benchmark Suite

```elixir
# benchmarks/node_execution_bench.exs
Benchee.run(
  %{
    "condition_node" => fn -> Condition.execute(config, context) end,
    "ab_split_node" => fn -> ABSplit.execute(config, context) end,
    "wait_node_setup" => fn -> Wait.execute(config, context) end,
    "template_render" => fn -> TemplateRenderer.render(template, vars) end,
    "segment_evaluate" => fn -> SegmentEvaluator.customer_matches?(cid, seg) end,
    "frequency_check" => fn -> FrequencyCap.check(cid, :email) end
  },
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.HTML, file: "benchmarks/output/nodes.html"}
  ]
)
```

---

## 5. Pre-release Checklist

Before every version release:

- [ ] All unit tests pass (> 90% coverage)
- [ ] All integration tests pass
- [ ] All property-based tests pass (> 500 scenarios)
- [ ] All chaos tests pass
- [ ] All load tests meet performance targets
- [ ] Reliability Report generated and attached to release
- [ ] Benchmark comparison with previous version (no regressions)
- [ ] Docker image builds and starts successfully
- [ ] docker-compose up brings entire stack to healthy state
- [ ] Zero-downtime rolling restart verified
- [ ] Dialyzer passes with no warnings
- [ ] Credo strict mode passes
- [ ] No compiler warnings
