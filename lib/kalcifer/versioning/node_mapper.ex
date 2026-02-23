defmodule Kalcifer.Versioning.NodeMapper do
  @moduledoc false

  @wait_types ~w(wait wait_until wait_for_event)

  @doc """
  Builds a mapping between old and new graph versions by matching node IDs.
  Returns matched, removed, and added nodes.
  """
  def build_mapping(old_graph, new_graph) do
    old_nodes = index_nodes(old_graph)
    new_nodes = index_nodes(new_graph)

    old_ids = MapSet.new(Map.keys(old_nodes))
    new_ids = MapSet.new(Map.keys(new_nodes))

    matched_ids = MapSet.intersection(old_ids, new_ids)
    removed_ids = MapSet.difference(old_ids, new_ids)
    added_ids = MapSet.difference(new_ids, old_ids)

    matched =
      Enum.map(matched_ids, fn id ->
        v1 = Map.fetch!(old_nodes, id)
        v2 = Map.fetch!(new_nodes, id)
        %{id: id, v1_node: v1, v2_node: v2, changes: detect_changes(v1, v2)}
      end)

    removed = Enum.map(removed_ids, &Map.fetch!(old_nodes, &1))
    added = Enum.map(added_ids, &Map.fetch!(new_nodes, &1))

    %{matched: matched, removed: removed, added: added}
  end

  @doc """
  Checks if migration is safe for an instance on the given current_nodes.
  Returns :ok if all current nodes exist in the new version, or
  {:unsafe, :on_removed_node, removed_ids} if any are removed.
  """
  def check_migration_safety(current_nodes, node_map) do
    removed_ids = MapSet.new(Enum.map(node_map.removed, & &1["id"]))

    on_removed =
      current_nodes
      |> Enum.filter(&MapSet.member?(removed_ids, &1))

    case on_removed do
      [] -> :ok
      ids -> {:unsafe, :on_removed_node, ids}
    end
  end

  @doc """
  Detects wait-related config changes in matched nodes.
  Returns a list of {node_id, change_type} tuples.
  """
  def detect_wait_changes(node_map) do
    node_map.matched
    |> Enum.filter(fn %{v1_node: v1} -> v1["type"] in @wait_types end)
    |> Enum.flat_map(&wait_change_for/1)
  end

  # --- Private ---

  defp index_nodes(graph) do
    graph
    |> Map.get("nodes", [])
    |> Map.new(&{&1["id"], &1})
  end

  defp detect_changes(v1, v2) do
    changes = []
    changes = if v1["type"] != v2["type"], do: [:type_changed | changes], else: changes
    changes = if v1["config"] != v2["config"], do: [:config_changed | changes], else: changes
    changes
  end

  defp wait_change_for(%{id: id, v1_node: v1, v2_node: v2, changes: changes}) do
    if :config_changed in changes do
      specific_changes(id, v1, v2)
    else
      []
    end
  end

  defp specific_changes(id, %{"type" => "wait_for_event"} = v1, v2) do
    changes = []

    changes =
      if v1["config"]["event_type"] != v2["config"]["event_type"],
        do: [{id, :event_type_changed} | changes],
        else: changes

    changes =
      if v1["config"]["timeout"] != v2["config"]["timeout"],
        do: [{id, :timeout_changed} | changes],
        else: changes

    changes
  end

  defp specific_changes(id, %{"type" => "wait"} = v1, v2) do
    if v1["config"]["duration"] != v2["config"]["duration"] do
      [{id, :duration_changed}]
    else
      []
    end
  end

  defp specific_changes(id, %{"type" => "wait_until"} = v1, v2) do
    if v1["config"]["datetime"] != v2["config"]["datetime"] do
      [{id, :duration_changed}]
    else
      []
    end
  end

  defp specific_changes(_id, _v1, _v2), do: []
end
