defmodule Kalcifer.Engine.GraphWalker do
  @moduledoc false

  @entry_types ~w(segment_entry event_entry webhook_entry)

  def entry_nodes(graph) do
    graph
    |> nodes()
    |> Enum.filter(fn node -> node["type"] in @entry_types end)
  end

  def find_node(graph, node_id) do
    Enum.find(nodes(graph), fn node -> node["id"] == node_id end)
  end

  def next_nodes(graph, node_id) do
    target_ids =
      graph
      |> outgoing_edges(node_id)
      |> Enum.map(fn edge -> edge["target"] end)

    Enum.filter(nodes(graph), fn node -> node["id"] in target_ids end)
  end

  def next_nodes(graph, node_id, branch_key) do
    target_ids =
      graph
      |> outgoing_edges(node_id)
      |> Enum.filter(fn edge -> edge["branch"] == branch_key end)
      |> Enum.map(fn edge -> edge["target"] end)

    Enum.filter(nodes(graph), fn node -> node["id"] in target_ids end)
  end

  def outgoing_edges(graph, node_id) do
    Enum.filter(edges(graph), fn edge -> edge["source"] == node_id end)
  end

  defp nodes(graph), do: Map.get(graph, "nodes", [])
  defp edges(graph), do: Map.get(graph, "edges", [])
end
