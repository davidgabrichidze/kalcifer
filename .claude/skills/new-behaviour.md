# /new-behaviour — Create a new Elixir behaviour

The user provides: behaviour name, callbacks, purpose.

## Steps

### 1. Create the behaviour module

File: `lib/kalcifer/{context}/{behaviour_name}.ex`

```elixir
defmodule Kalcifer.{Context}.{BehaviourName} do
  @moduledoc false

  @type config :: map()

  @callback function_name(arg1 :: type1(), arg2 :: type2()) ::
    {:ok, result()} | {:error, reason :: term()}

  # Optional callbacks
  @callback optional_fn(arg :: type()) :: :ok
  @optional_callbacks [optional_fn: 1]

  # If providing default implementations via __using__:
  defmacro __using__(_opts) do
    quote do
      @behaviour Kalcifer.{Context}.{BehaviourName}

      @impl true
      def optional_fn(_arg), do: :ok

      defoverridable optional_fn: 1
    end
  end
end
```

**Conventions**:
- Follow the pattern in `lib/kalcifer/engine/nodes/behaviour.ex`
- Use `@moduledoc false` unless the behaviour is public API
- Define `@type` specs for callback arguments
- Use `@optional_callbacks` for callbacks with sensible defaults
- Provide `__using__` macro if default implementations are useful
- Keep callback specs explicit with tagged tuples (`{:ok, _}` / `{:error, _}`)

### 2. Set up Mox mock (if needed for testing)

Add to `test/test_helper.exs` or `test/support/mocks.ex`:

```elixir
Mox.defmock(Kalcifer.{Context}.Mock{BehaviourName}, for: Kalcifer.{Context}.{BehaviourName})
```

Add to config/test.exs if the mock should be the default in tests:

```elixir
config :kalcifer, :{behaviour_key}, Kalcifer.{Context}.Mock{BehaviourName}
```

### 3. Create test for the behaviour contract

File: `test/kalcifer/{context}/{behaviour_name}_test.exs`

```elixir
defmodule Kalcifer.{Context}.{BehaviourName}Test do
  use Kalcifer.DataCase, async: true

  # Test that a module implementing the behaviour works correctly
  defmodule TestImpl do
    use Kalcifer.{Context}.{BehaviourName}
    # or: @behaviour Kalcifer.{Context}.{BehaviourName}

    @impl true
    def function_name(_arg1, _arg2), do: {:ok, %{}}
  end

  describe "contract" do
    test "implementation fulfills callbacks" do
      assert {:ok, _} = TestImpl.function_name("a", "b")
    end
  end
end
```

### 4. Verify

```bash
mix test --trace test/kalcifer/{context}/{behaviour_name}_test.exs
mix compile --warnings-as-errors
mix format
mix credo --strict
```
