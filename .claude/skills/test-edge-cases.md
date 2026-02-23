# /test-edge-cases — Write edge case tests for a module

The user specifies which module or feature to write edge case tests for.

## Steps

### 1. Read the target module

Understand:
- All public functions and their signatures
- All possible return values
- Input validation logic
- Error handling paths
- External dependencies (DB, ETS, GenServers)

### 2. Identify edge cases

For each function, consider:

**Input boundaries**:
- Empty maps `%{}`
- Missing required keys
- `nil` values
- Empty strings `""`
- Negative numbers, zero, very large numbers
- Invalid types (string where integer expected, etc.)
- Unicode / special characters in strings

**State boundaries**:
- Entity doesn't exist in DB
- Entity in unexpected status (archived flow, completed instance)
- Concurrent access (two processes modifying same record)
- ETS table empty or not started

**Time boundaries**:
- Timestamps at midnight, end of month, leap year
- Duration edge cases: "0s", "0d", negative durations
- Time windows that span across days

**Collection boundaries**:
- Empty lists `[]`
- Single-element lists
- Very large collections (1000+ items)
- Duplicate entries

**Graph boundaries** (specific to Kalcifer):
- Graph with single node (entry only, no edges)
- Graph with cycles (should be rejected)
- Disconnected nodes (orphans)
- Node referencing non-existent edge target
- Empty config on nodes that require config

### 3. Create test file

File: `test/kalcifer/{path}/{module_name}_edge_cases_test.exs`

Or add a new `describe` block to the existing test file if it makes more sense.

```elixir
defmodule Kalcifer.{Module}EdgeCasesTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.{Module}

  describe "function_name/N edge cases" do
    test "handles empty input" do
      assert {:error, _} = Module.function_name(%{})
    end

    test "handles nil values" do
      assert {:error, _} = Module.function_name(nil)
    end

    test "handles missing required fields" do
      assert {:error, _} = Module.function_name(%{"optional" => "value"})
    end

    test "handles concurrent access" do
      # Create shared resource
      resource = insert(:resource)

      tasks =
        for _ <- 1..5 do
          Task.async(fn ->
            Module.function_name(resource.id, %{update: "concurrent"})
          end)
        end

      results = Task.await_many(tasks)
      # Assert at least one succeeds, others handle gracefully
    end
  end
end
```

### 4. Conventions

- Group edge cases in `describe "{function}/N edge cases"` blocks
- Use descriptive test names: `"handles X when Y"` or `"returns error for Z"`
- Each test should test ONE edge case (not multiple)
- Use `assert_raise` for expected exceptions
- For GenServer tests, use `catch_exit` for expected exits
- For DB constraint violations, assert on changeset errors

### 5. Verify

```bash
mix test --trace test/kalcifer/{path}/{test_file}.exs
mix compile --warnings-as-errors
```
