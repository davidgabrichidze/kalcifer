defmodule Kalcifer.Flows.FlowGraph do
  @moduledoc false

  @entry_types ~w(segment_entry event_entry webhook_entry)
  @branching_types ~w(condition ab_split wait_for_event)

  @doc """
  Validates a flow graph structure.

  A graph is a map with "nodes" (list of node maps) and "edges" (list of edge maps).
  Each node has "id" and "type". Each edge has "source" and "target", with optional "branch".
  """
  def validate(graph) when is_map(graph) do
    with :ok <- validate_has_entry(graph),
         :ok <- validate_edges_reference_valid_nodes(graph),
         :ok <- validate_no_cycles(graph),
         :ok <- validate_no_orphans(graph),
         :ok <- validate_branch_edges_complete(graph) do
      :ok
    end
  end

  def validate(_), do: {:error, ["graph must be a map"]}

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
          |> MapSet.new()

        required = required_branches(node)
        missing = MapSet.difference(required, outgoing_branches)

        if MapSet.size(missing) == 0 do
          []
        else
          missing_list = MapSet.to_list(missing) |> Enum.join(", ")
          ["node #{node["id"]} (#{node["type"]}) missing branch edges: #{missing_list}"]
        end
      end)

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  defp required_branches(%{"type" => "condition"}), do: MapSet.new(["true", "false"])

  defp required_branches(%{"type" => "wait_for_event", "config" => config}) when is_map(config) do
    timeout = Map.get(config, "timeout_branch", "timed_out")
    event = Map.get(config, "event_branch", "event_received")
    MapSet.new([timeout, event])
  end

  defp required_branches(%{"type" => "wait_for_event"}) do
    MapSet.new(["timed_out", "event_received"])
  end

  defp required_branches(%{"type" => "ab_split", "config" => %{"variants" => variants}})
       when is_list(variants) do
    variants |> Enum.map(& &1["key"]) |> Enum.reject(&is_nil/1) |> MapSet.new()
  end

  defp required_branches(%{"type" => "ab_split"}) do
    MapSet.new()
  end

  defp required_branches(_), do: MapSet.new()
end
