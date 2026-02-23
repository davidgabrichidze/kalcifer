# /test-e2e — Write end-to-end integration test

Create an E2E test that exercises a full flow path through the API and engine.
The user describes the scenario to test.

## Reference

See `test/kalcifer/integration/trigger_to_completion_test.exs` for the canonical pattern.

## Steps

### 1. Determine what's being tested

E2E tests should cover a complete path:
- API call → Engine execution → DB state verification
- Multi-node graph traversal with branching
- Wait + resume via events or timeouts
- Deduplication and idempotency
- Cross-feature interactions (e.g. frequency cap + branching)

### 2. Create test file

File: `test/kalcifer/integration/{scenario_name}_test.exs`

```elixir
defmodule Kalcifer.Integration.{ScenarioName}Test do
  @moduledoc """
  E2E: {describe what the test covers}
  """
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Flows.ExecutionStep
  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Tenants

  @raw_api_key "e2e_test_key_{scenario}"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  test "describe the full scenario", %{conn: conn} do
    # Step 1: Create flow via API
    conn_create = post(conn, "/api/v1/flows", %{"name" => "E2E Test Flow"})
    assert %{"data" => %{"id" => flow_id}} = json_response(conn_create, 201)

    # Step 2: Add version with test graph
    graph = build_test_graph()
    conn_version = post(conn, "/api/v1/flows/#{flow_id}/versions", %{
      "graph" => graph,
      "changelog" => "E2E test"
    })
    assert %{"data" => %{"version_number" => 1}} = json_response(conn_version, 201)

    # Step 3: Activate
    post(conn, "/api/v1/flows/#{flow_id}/activate")

    # Step 4: Trigger
    customer_id = "e2e_#{System.unique_integer([:positive])}"
    conn_trigger = post(conn, "/api/v1/flows/#{flow_id}/trigger", %{
      "customer_id" => customer_id
    })
    assert %{"instance_id" => instance_id} = json_response(conn_trigger, 201)

    # Step 5: Wait for execution / interact
    Process.sleep(200)

    # For waiting flows: monitor the process
    via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}
    pid = GenServer.whereis(via)

    # If testing wait+resume:
    ref = Process.monitor(pid)
    # Send event / wait for timeout
    # ...

    # Step 6: Verify final state
    instance = Kalcifer.Repo.get!(FlowInstance, instance_id)
    assert instance.status == "completed"

    # Verify execution path
    import Ecto.Query
    steps = Kalcifer.Repo.all(
      from s in ExecutionStep, where: s.instance_id == ^instance_id
    )
    node_ids = Enum.map(steps, & &1.node_id)

    assert "expected_node" in node_ids
    refute "skipped_node" in node_ids
  end

  defp build_test_graph do
    %{
      "nodes" => [
        # Build graph nodes matching the scenario
      ],
      "edges" => [
        # Build edges
      ]
    }
  end
end
```

### Key patterns

**Waiting for FlowServer to complete**:
```elixir
ref = Process.monitor(pid)
receive do
  {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
after
  3000 -> flunk("FlowServer did not complete")
end
```

**Sending events to resume waiting nodes**:
```elixir
post(conn, "/api/v1/events", %{
  "customer_id" => customer_id,
  "event_type" => "event_name",
  "data" => %{}
})
```

**Verifying execution path** (which nodes were visited):
```elixir
steps = Repo.all(from s in ExecutionStep, where: s.instance_id == ^instance_id)
node_ids = Enum.map(steps, & &1.node_id)
assert "node_a" in node_ids
refute "node_b" in node_ids
```

**Testing dedup**:
```elixir
# Second trigger should be blocked
conn_t2 = post(conn, "/api/v1/flows/#{flow_id}/trigger", %{"customer_id" => customer_id})
assert json_response(conn_t2, 409) == %{"error" => "already_in_flow"}
```

### 3. Use `async: false`

E2E tests interact with shared state (GenServers, ETS, DB) — always `async: false`.

### 4. Verify

```bash
mix test --trace test/kalcifer/integration/{scenario_name}_test.exs
```
