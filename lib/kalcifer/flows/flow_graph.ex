defmodule Kalcifer.Flows.FlowGraph do
  @moduledoc false

  @entry_types ~w(segment_entry event_entry webhook_entry)
  @end_types ~w(exit goal_reached)
  @branching_types ~w(condition ab_split wait_for_event check_segment preference_gate frequency_cap ai_decide)

  @doc """
  Validates a flow graph structure.

  A graph is a map with "nodes" (list of node maps) and "edges" (list of edge maps).
  Each node has "id" and "type". Each edge has "source" and "target", with optional "branch".
  """
  def validate(graph, opts \\ [])

  def validate(graph, opts) when is_map(graph) do
    allow_cycles = Keyword.get(opts, :allow_cycles, false)

    with :ok <- validate_has_entry(graph),
         :ok <- validate_no_duplicate_ids(graph),
         :ok <- validate_edges_reference_valid_nodes(graph),
         :ok <- maybe_validate_no_cycles(graph, allow_cycles),
         :ok <- validate_no_orphans(graph),
         :ok <- validate_branch_edges_complete(graph),
         :ok <- validate_has_end(graph) do
      :ok
    end
  end

  def validate(_, _opts), do: {:error, ["graph must be a map"]}

  defp maybe_validate_no_cycles(_graph, true), do: :ok
  defp maybe_validate_no_cycles(graph, false), do: validate_no_cycles(graph)

  @doc """
  Validates that all node types in the graph are registered in the given registry.

  Returns `:ok` or `{:error, [String.t()]}` with unknown type errors.
  The registry must implement `lookup/1` returning `{:ok, module}` or `:error`.
  """
  def validate_node_types(graph, registry) when is_map(graph) do
    errors =
      nodes(graph)
      |> Enum.flat_map(fn node ->
        type = node["type"]

        case registry.lookup(type) do
          {:ok, _module} -> []
          :error -> ["unknown node type: #{type}"]
        end
      end)
      |> Enum.uniq()

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  @doc """
  Validates each node's config by calling `module.validate/1` via the registry.

  Returns `:ok` or `{:error, [String.t()]}` with config validation errors.
  Nodes with unknown types are skipped (use `validate_node_types/2` first).
  """
  def analyze_config_completeness(graph, registry) when is_map(graph) do
    errors =
      nodes(graph)
      |> Enum.flat_map(&validate_node_config(&1, registry))

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  defp validate_node_config(node, registry) do
    case registry.lookup(node["type"]) do
      {:ok, module} ->
        config = node["config"] || %{}
        errors = required_config_errors(module, config) ++ custom_config_errors(module, config)
        Enum.map(errors, &"node #{node["id"]} (#{node["type"]}): #{&1}")

      _ ->
        []
    end
  end

  # Generic check against the node's config_schema: every field marked
  # required must be present and non-empty. Catches nodes that do not
  # implement a custom validate/1 (e.g. wait_for_event without an
  # event_type would otherwise wait forever, un-resumable).
  defp required_config_errors(module, config) do
    if function_exported?(module, :config_schema, 0) do
      do_required_config_errors(module, config)
    else
      []
    end
  end

  defp do_required_config_errors(module, config) do
    module.config_schema()
    |> Enum.filter(fn {_field, spec} -> spec["required"] == true end)
    |> Enum.reject(fn {field, _spec} -> present?(config[field]) end)
    |> Enum.map(fn {field, _spec} -> "missing required config field \"#{field}\"" end)
  end

  defp custom_config_errors(module, config) do
    case module.validate(config) do
      {:error, reasons} -> reasons
      _ -> []
    end
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true

  @doc """
  Extracts context field names referenced by condition nodes in the graph.

  Returns a list of field name strings that condition nodes read from context.
  """
  def analyze_context_deps(graph) when is_map(graph) do
    nodes(graph)
    |> Enum.flat_map(&extract_context_field/1)
    |> Enum.uniq()
  end

  defp extract_context_field(%{"type" => "condition", "config" => config}),
    do: extract_field(config, "field")

  defp extract_context_field(%{"type" => "condition"} = _node),
    do: []

  defp extract_context_field(%{"type" => "check_segment", "config" => config}),
    do: extract_field(config, "segment_field")

  defp extract_context_field(%{"type" => "check_segment"} = _node),
    do: []

  defp extract_context_field(_node), do: []

  defp extract_field(config, key) do
    field = (config || %{})[key]
    if is_binary(field) and field != "", do: [field], else: []
  end

  @doc """
  Runs full pre-flight analysis on a graph: structural validation, node type
  validation, config completeness, and context dependency extraction.

  Returns `{:ok, %{warnings: [String.t()], context_deps: [String.t()]}}` or
  `{:error, [String.t()]}` for critical failures.
  """
  def preflight(graph, registry, opts \\ []) when is_map(graph) do
    with :ok <- validate(graph, opts),
         :ok <- validate_node_types(graph, registry) do
      config_warnings =
        case analyze_config_completeness(graph, registry) do
          :ok -> []
          {:error, errors} -> errors
        end

      context_deps = analyze_context_deps(graph)

      {:ok, %{warnings: config_warnings, context_deps: context_deps}}
    end
  end

  defp nodes(graph), do: Map.get(graph, "nodes", [])
  defp edges(graph), do: Map.get(graph, "edges", [])

  defp node_ids(graph), do: MapSet.new(nodes(graph), & &1["id"])

  defp entry_nodes(graph) do
    Enum.filter(nodes(graph), fn node -> node["type"] in @entry_types end)
  end

  # --- Validations ---

  defp validate_has_entry(graph) do
    case entry_nodes(graph) do
      [] -> {:error, ["graph must have at least one entry node"]}
      _ -> :ok
    end
  end

  defp validate_has_end(graph) do
    has_end = Enum.any?(nodes(graph), fn node -> node["type"] in @end_types end)

    if has_end do
      :ok
    else
      {:error, ["graph must have at least one end node (exit or goal_reached)"]}
    end
  end

  defp validate_no_duplicate_ids(graph) do
    ids = Enum.map(nodes(graph), & &1["id"])
    duplicates = ids -- Enum.uniq(ids)

    if duplicates == [] do
      :ok
    else
      dupes = Enum.uniq(duplicates)
      {:error, Enum.map(dupes, &"duplicate node id: #{&1}")}
    end
  end

  defp validate_edges_reference_valid_nodes(graph) do
    valid_ids = node_ids(graph)

    invalid =
      edges(graph)
      |> Enum.flat_map(fn edge ->
        errors = []

        errors =
          if edge["source"] in valid_ids,
            do: errors,
            else: ["edge references unknown source node: #{edge["source"]}" | errors]

        errors =
          if edge["target"] in valid_ids,
            do: errors,
            else: ["edge references unknown target node: #{edge["target"]}" | errors]

        errors
      end)

    case invalid do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # Cycle detection using Kahn's topological sort algorithm.
  # If not all nodes are consumed, the remaining nodes form a cycle.
  defp validate_no_cycles(graph) do
    node_set = node_ids(graph)
    edge_list = edges(graph)

    # Build in-degree map
    in_degree =
      Enum.reduce(node_set, %{}, fn id, acc -> Map.put(acc, id, 0) end)

    in_degree =
      Enum.reduce(edge_list, in_degree, fn edge, acc ->
        Map.update(acc, edge["target"], 1, &(&1 + 1))
      end)

    # Build adjacency list
    adjacency =
      Enum.reduce(edge_list, %{}, fn edge, acc ->
        Map.update(acc, edge["source"], [edge["target"]], &[edge["target"] | &1])
      end)

    # Start with nodes that have no incoming edges
    queue =
      in_degree
      |> Enum.filter(fn {_id, deg} -> deg == 0 end)
      |> Enum.map(fn {id, _} -> id end)

    processed = kahns_loop(queue, adjacency, in_degree, 0)

    if processed == MapSet.size(node_set) do
      :ok
    else
      {:error, ["graph contains a cycle"]}
    end
  end

  defp kahns_loop([], _adjacency, _in_degree, count), do: count

  defp kahns_loop([node | rest], adjacency, in_degree, count) do
    neighbors = Map.get(adjacency, node, [])

    {new_queue, new_in_degree} =
      Enum.reduce(neighbors, {rest, in_degree}, fn neighbor, {q, deg} ->
        new_deg = Map.update!(deg, neighbor, &(&1 - 1))

        if new_deg[neighbor] == 0 do
          {[neighbor | q], new_deg}
        else
          {q, new_deg}
        end
      end)

    kahns_loop(new_queue, adjacency, new_in_degree, count + 1)
  end

  # Orphan detection via BFS from all entry nodes.
  # Any node not reachable from an entry is an orphan.
  defp validate_no_orphans(graph) do
    entries = entry_nodes(graph) |> Enum.map(& &1["id"])
    all_ids = node_ids(graph)

    adjacency =
      Enum.reduce(edges(graph), %{}, fn edge, acc ->
        Map.update(acc, edge["source"], [edge["target"]], &[edge["target"] | &1])
      end)

    reachable = bfs(entries, adjacency, MapSet.new(entries))
    orphans = MapSet.difference(all_ids, reachable)

    if MapSet.size(orphans) == 0 do
      :ok
    else
      orphan_list = MapSet.to_list(orphans) |> Enum.join(", ")
      {:error, ["orphan nodes not reachable from entry: #{orphan_list}"]}
    end
  end

  defp bfs([], _adjacency, visited), do: visited

  defp bfs([node | rest], adjacency, visited) do
    neighbors = Map.get(adjacency, node, [])

    {new_queue, new_visited} =
      Enum.reduce(neighbors, {rest, visited}, fn neighbor, {q, v} ->
        if MapSet.member?(v, neighbor) do
          {q, v}
        else
          {q ++ [neighbor], MapSet.put(v, neighbor)}
        end
      end)

    bfs(new_queue, adjacency, new_visited)
  end

  # Validates that branching node types have edges for all required branches.
  defp validate_branch_edges_complete(graph) do
    edge_list = edges(graph)

    errors =
      nodes(graph)
      |> Enum.filter(fn node -> node["type"] in @branching_types end)
      |> Enum.flat_map(fn node ->
        outgoing_branches =
          edge_list
          |> Enum.filter(fn e -> e["source"] == node["id"] end)
          |> Enum.map(fn e -> e["branch"] end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        required = required_branches(node)
        missing = required -- outgoing_branches

        if missing == [] do
          []
        else
          missing_list = Enum.join(missing, ", ")
          ["node #{node["id"]} (#{node["type"]}) missing branch edges: #{missing_list}"]
        end
      end)

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  @spec required_branches(map()) :: [String.t()]
  defp required_branches(%{"type" => "condition"}), do: ["true", "false"]

  defp required_branches(%{"type" => "wait_for_event", "config" => config}) when is_map(config) do
    timeout = Map.get(config, "timeout_branch", "timed_out")
    event = Map.get(config, "event_branch", "event_received")
    [timeout, event]
  end

  defp required_branches(%{"type" => "wait_for_event"}) do
    ["timed_out", "event_received"]
  end

  defp required_branches(%{"type" => "ab_split", "config" => %{"variants" => variants}})
       when is_list(variants) do
    variants |> Enum.map(& &1["key"]) |> Enum.reject(&is_nil/1)
  end

  defp required_branches(%{"type" => "ab_split"}) do
    []
  end

  defp required_branches(%{"type" => "check_segment"}), do: ["true", "false"]
  defp required_branches(%{"type" => "preference_gate"}), do: ["true", "false"]
  defp required_branches(%{"type" => "frequency_cap"}), do: ["capped", "allowed"]

  defp required_branches(%{"type" => "ai_decide", "config" => %{"branches" => branches}})
       when is_list(branches) do
    branches
  end

  defp required_branches(%{"type" => "ai_decide"}), do: []

  defp required_branches(_), do: []

  # ── Suggestions ─────────────────────────────────────────────

  @doc """
  Generates improvement suggestions for a flow graph.
  Returns a list of human-readable suggestion strings (Georgian).
  """
  @spec suggestions(map()) :: [String.t()]
  def suggestions(graph) when is_map(graph) do
    nodes = Map.get(graph, "nodes", [])
    edges = Map.get(graph, "edges", [])

    []
    |> suggest_missing_end(nodes, edges)
    |> suggest_missing_entry(nodes)
    |> suggest_orphan_nodes(nodes, edges)
    |> suggest_incomplete_branches(nodes, edges)
    |> suggest_single_node(nodes)
    |> Enum.reverse()
  end

  def suggestions(_), do: []

  defp suggest_missing_end(acc, nodes, _edges) do
    end_types = ~w(end exit goal_reached)
    has_end = Enum.any?(nodes, &(&1["type"] in end_types))

    if not has_end and length(nodes) > 1 do
      ["ფლოუს არ აქვს დასასრული (end) — დაამატე რომ სწორად დასრულდეს" | acc]
    else
      acc
    end
  end

  defp suggest_missing_entry(acc, nodes) do
    has_entry = Enum.any?(nodes, &(&1["type"] in @entry_types))

    if not has_entry and nodes != [] do
      ["ფლოუს არ აქვს შესასვლელი (entry) — დაამატე trigger node" | acc]
    else
      acc
    end
  end

  defp suggest_orphan_nodes(acc, nodes, edges) do
    connected =
      MapSet.new(Enum.flat_map(edges, fn e -> [e["source"], e["target"]] end))

    orphans =
      nodes
      |> Enum.reject(&(&1["id"] |> then(fn id -> MapSet.member?(connected, id) end)))
      |> Enum.map(& &1["id"])

    if orphans != [] and length(nodes) > 1 do
      ids = Enum.join(orphans, ", ")
      ["იზოლირებული ნაბიჯები: #{ids} — შეაერთე სხვა ნაბიჯებთან" | acc]
    else
      acc
    end
  end

  defp suggest_incomplete_branches(acc, nodes, edges) do
    nodes
    |> Enum.filter(&(&1["type"] in @branching_types))
    |> Enum.reduce(acc, fn node, suggestions ->
      if incomplete_branching?(node, edges) do
        ["#{node["id"]} (#{node["type"]}) — ორივე branch უნდა იყოს დაკავშირებული" | suggestions]
      else
        suggestions
      end
    end)
  end

  # A branching node needs at least two outgoing edges — one per branch.
  defp incomplete_branching?(node, edges) do
    outgoing = Enum.filter(edges, &(&1["source"] == node["id"]))
    not match?([_, _ | _], outgoing)
  end

  defp suggest_single_node(acc, nodes) do
    if length(nodes) == 1 do
      ["ფლოუში მხოლოდ ერთი ნაბიჯია — დაამატე მეტი ლოგიკა" | acc]
    else
      acc
    end
  end
end
