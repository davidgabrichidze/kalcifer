defmodule Kalcifer.Engine.Nodes.Action.Data.MemoryRecall do
  @moduledoc """
  Retrieves operator memories and injects them into flow context.

  Config:
    - keys: list of memory keys to recall (optional — if empty, recalls all)
    - category: filter by category (optional: "general", "preference", "pattern", "context")
    - context_key: where to store results in context (default: "memories")

  Results are stored in context.accumulated under the node ID.
  """

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.AI.Context

  @impl true
  def execute(config, context) do
    tenant_id = context["_tenant_id"]

    if context["_dry_run"] do
      {:completed,
       %{
         dry_run: true,
         would_recall: %{
           keys: config["keys"],
           category: config["category"],
           context_key: config["context_key"] || "memories"
         }
       }}
    else
      recall_memories(config, tenant_id)
    end
  end

  @impl true
  def config_schema do
    %{
      "keys" => %{
        "type" => "array",
        "description" => "Specific memory keys to recall (empty = all)"
      },
      "category" => %{
        "type" => "string",
        "enum" => ["general", "preference", "pattern", "context"],
        "description" => "Filter by memory category"
      },
      "context_key" => %{
        "type" => "string",
        "default" => "memories",
        "description" => "Context key where recalled memories are stored"
      }
    }
  end

  @impl true
  def category, do: :action

  defp recall_memories(config, tenant_id) do
    memories = Context.list_memories(tenant_id)

    # Filter by category
    memories =
      case config["category"] do
        nil -> memories
        cat -> Enum.filter(memories, &(&1.category == cat))
      end

    # Filter by keys
    memories =
      case config["keys"] do
        nil -> memories
        [] -> memories
        keys when is_list(keys) -> Enum.filter(memories, &(&1.key in keys))
        _ -> memories
      end

    # Convert to map
    memory_map =
      memories
      |> Enum.map(fn m -> {m.key, m.value} end)
      |> Map.new()

    {:completed,
     %{
       memories: memory_map,
       count: map_size(memory_map),
       context_key: config["context_key"] || "memories"
     }}
  rescue
    _ ->
      {:completed, %{memories: %{}, count: 0, error: "Failed to recall memories"}}
  end
end
