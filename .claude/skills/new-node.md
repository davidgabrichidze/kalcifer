# /new-node — Create a new engine node

Create a new node for the Kalcifer flow engine. The user provides: node name, category, and registry key.

## Steps

### 1. Determine placement

Based on the category, determine the directory and module path:

| Category | Directory | Module prefix |
|----------|-----------|---------------|
| `trigger` | `lib/kalcifer/engine/nodes/trigger/` | `Kalcifer.Engine.Nodes.Trigger` |
| `condition` | `lib/kalcifer/engine/nodes/condition/` | `Kalcifer.Engine.Nodes.Condition` |
| `wait` | `lib/kalcifer/engine/nodes/wait/` | `Kalcifer.Engine.Nodes.Wait` |
| `action/channel` | `lib/kalcifer/engine/nodes/action/channel/` | `Kalcifer.Engine.Nodes.Action.Channel` |
| `action/data` | `lib/kalcifer/engine/nodes/action/data/` | `Kalcifer.Engine.Nodes.Action.Data` |
| `end` | `lib/kalcifer/engine/nodes/end/` | `Kalcifer.Engine.Nodes.End` |

**No "Node" suffix** in module names. E.g. `FrequencyCap`, not `FrequencyCapNode`.

### 2. Create the node module

File: `lib/kalcifer/engine/nodes/{category}/{snake_case_name}.ex`

```elixir
defmodule Kalcifer.Engine.Nodes.{Category}.{PascalCaseName} do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, context) do
    # TODO: implement
    {:completed, %{}}
  end

  @impl true
  def config_schema do
    %{
      # "field_name" => %{"type" => "string", "required" => true}
    }
  end

  @impl true
  def category, do: :{category_atom}
end
```

For `condition` nodes, use `{:branched, branch_key, result}` instead of `{:completed, result}`.
For `wait` nodes, implement `resume/3` and return `{:waiting, wait_config}` from execute.

### 3. Register in NodeRegistry

Edit `lib/kalcifer/engine/node_registry.ex`. Add the new entry to `@built_in_nodes` map.
Registry key is a snake_case string matching the graph JSON type field.
**Keep entries in the map sorted logically by category group**.

### 4. Create the test

File: `test/kalcifer/engine/nodes/{snake_case_name}_test.exs`

```elixir
defmodule Kalcifer.Engine.Nodes.{Category}.{PascalCaseName}Test do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Engine.Nodes.{Category}.{PascalCaseName}

  describe "execute/2" do
    test "basic execution" do
      config = %{}
      context = %{}
      assert {:completed, result} = {PascalCaseName}.execute(config, context)
    end
  end

  describe "config_schema/0" do
    test "returns a map" do
      assert is_map({PascalCaseName}.config_schema())
    end
  end

  describe "category/0" do
    test "returns :{category_atom}" do
      assert {PascalCaseName}.category() == :{category_atom}
    end
  end
end
```

If the node uses DB data (like FrequencyCap), add `import Kalcifer.Factory` and create test fixtures.

### 5. Verify

Run:
```bash
mix test --trace test/kalcifer/engine/nodes/{snake_case_name}_test.exs
mix compile --warnings-as-errors
mix format
mix credo --strict
```

### 6. Update node count

Update the count of built-in nodes in CLAUDE.md (search for "built-in nodes across").
