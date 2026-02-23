# /new-oban-job — Create a new Oban worker

The user provides: job name, queue, purpose.

## Steps

### 1. Create the worker module

File: `lib/kalcifer/engine/jobs/{snake_case_name}.ex`

```elixir
defmodule Kalcifer.Engine.Jobs.{PascalCaseName} do
  @moduledoc false

  use Oban.Worker, queue: :{queue_name}, max_attempts: 3

  @impl true
  def perform(%Oban.Job{args: %{"key" => value}}) do
    # Implementation here
    :ok
  end
end
```

**Available queues** (defined in config/config.exs):
- `:flow_triggers` (concurrency: 10) — flow entry evaluation
- `:delayed_resume` (concurrency: 20) — wait/timer node timeouts
- `:maintenance` (concurrency: 5) — cleanup, archival

If a new queue is needed, add it to `config/config.exs` under `config :kalcifer, Oban`.

**Conventions**:
- Jobs return `:ok` on success, `{:error, reason}` on retriable failure, `{:cancel, reason}` to stop retries
- Job args are string-keyed maps (JSON serialized)
- Use `String.to_existing_atom/1` for atom conversion from args (NOT `String.to_atom/1`)
- `max_attempts: 3` is default; adjust based on idempotency guarantees

### 2. Create test

File: `test/kalcifer/engine/jobs/{snake_case_name}_test.exs`

```elixir
defmodule Kalcifer.Engine.Jobs.{PascalCaseName}Test do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Engine.Jobs.{PascalCaseName}

  describe "perform/1" do
    test "processes job successfully" do
      # Setup: create necessary DB records
      job = %Oban.Job{args: %{"key" => "value"}}
      assert :ok = {PascalCaseName}.perform(job)
    end

    test "handles missing data gracefully" do
      job = %Oban.Job{args: %{}}
      # Assert appropriate behavior
    end
  end
end
```

**Testing conventions**:
- Oban is in `:manual` mode in test.exs — jobs are stored but not auto-executed
- Test the `perform/1` function directly by constructing `%Oban.Job{}` structs
- Do NOT rely on Oban inline mode for FlowServer interaction tests

### 3. Verify

```bash
mix test --trace test/kalcifer/engine/jobs/{snake_case_name}_test.exs
mix compile --warnings-as-errors
mix format
mix credo --strict
```
