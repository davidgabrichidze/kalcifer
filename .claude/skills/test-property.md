# /test-property — Write property-based tests with StreamData

The user specifies which module or function to test with property-based testing.

## Steps

### 1. Identify properties

Think about invariants that should ALWAYS hold:
- "For any valid input, the output should always satisfy X"
- "Encoding then decoding should return the original"
- "The result should always be within bounds"
- "For any graph, validation either passes or returns specific errors"

### 2. Create test file

File: `test/property/{module_name}_property_test.exs`

```elixir
defmodule Kalcifer.{Module}PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # --- Generators ---

  defp node_type_gen do
    member_of([
      "event_entry", "segment_entry", "webhook_entry",
      "send_email", "send_sms", "send_push", "send_whatsapp",
      "call_webhook", "send_in_app",
      "wait", "wait_until", "wait_for_event",
      "condition", "ab_split", "frequency_cap",
      "check_segment", "preference_gate",
      "update_profile", "add_tag", "custom_code", "track_conversion",
      "exit", "goal_reached"
    ])
  end

  defp node_gen do
    gen all id <- string(:alphanumeric, min_length: 1, max_length: 20),
            type <- node_type_gen(),
            x <- integer(0..1000),
            y <- integer(0..1000) do
      %{
        "id" => id,
        "type" => type,
        "position" => %{"x" => x, "y" => y},
        "config" => %{}
      }
    end
  end

  defp edge_gen(source_ids, target_ids) do
    gen all source <- member_of(source_ids),
            target <- member_of(target_ids),
            id <- string(:alphanumeric, min_length: 1, max_length: 10) do
      %{"id" => id, "source" => source, "target" => target}
    end
  end

  defp duration_string_gen do
    gen all num <- positive_integer(),
            unit <- member_of(["s", "m", "h", "d"]) do
      "#{num}#{unit}"
    end
  end

  # --- Properties ---

  property "duration parsing always returns positive seconds for valid input" do
    check all duration_str <- duration_string_gen() do
      case Kalcifer.Engine.Duration.parse(duration_str) do
        {:ok, seconds} -> assert seconds > 0
        {:error, _} -> :ok  # Invalid input is fine
      end
    end
  end

  property "config_schema returns a map for every registered node type" do
    check all type <- node_type_gen() do
      {:ok, module} = Kalcifer.Engine.NodeRegistry.lookup(type)
      schema = module.config_schema()
      assert is_map(schema)
    end
  end

  property "category returns a valid atom for every registered node type" do
    check all type <- node_type_gen() do
      {:ok, module} = Kalcifer.Engine.NodeRegistry.lookup(type)
      category = module.category()
      assert category in [:trigger, :condition, :wait, :action, :end]
    end
  end
end
```

### 3. Key StreamData generators

```elixir
# Basic types
string(:alphanumeric, min_length: 1)
integer(0..100)
positive_integer()
float(min: 0.0, max: 1.0)
boolean()
constant("fixed_value")
member_of(["a", "b", "c"])

# Composite
list_of(integer(), min_length: 1, max_length: 10)
map_of(string(:alphanumeric), integer())
tuple({string(:alphanumeric), integer()})

# Custom with gen all
gen all name <- string(:alphanumeric, min_length: 1),
        age <- integer(0..120) do
  %{name: name, age: age}
end

# Filtering
filter(integer(), &(&1 != 0))  # non-zero integers
```

### 4. Conventions

- Place property tests in `test/property/` directory
- Use `async: true` when possible
- Keep generators focused and composable
- Name properties as invariant statements: `"X always holds for Y"`
- Use `check all` with explicit generators
- Default iteration count (100) is usually sufficient; increase with `max_runs: 500` for critical paths
- Note: property tests need `use ExUnitProperties` (from StreamData dep)
- NodeRegistry must be running for node-related property tests — use `async: false` if needed

### 5. Verify

```bash
mix test --trace test/property/{module_name}_property_test.exs
```
