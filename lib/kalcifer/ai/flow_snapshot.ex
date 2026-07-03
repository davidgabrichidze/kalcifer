defmodule Kalcifer.AI.FlowSnapshot do
  @moduledoc """
  Renders a compact text snapshot of a conversation's linked flow graph for
  injection into the AI system prompt. Read-only — never creates versions.

  Returns nil when the conversation has no linked flow, the flow or its
  versions are missing, the flow belongs to a different tenant, or anything
  fails to load — the chat must keep working without a snapshot. Snapshot
  build failures are logged and skipped.
  """

  require Logger

  alias Kalcifer.AI.Context
  alias Kalcifer.Flows

  # Per-node config JSON longer than this gets truncated.
  @max_config_chars 200
  # Above this many nodes, configs are omitted entirely (ids/types/edges kept).
  @config_node_limit 30

  @spec for_conversation(String.t(), String.t() | nil) :: String.t() | nil
  def for_conversation(_tenant_id, nil), do: nil

  def for_conversation(tenant_id, conversation_id) do
    with %{entity_type: "flow", entity_id: flow_id} when not is_nil(flow_id) <-
           Context.get_conversation(tenant_id, conversation_id),
         %{} = flow <- Flows.get_flow(flow_id),
         true <- flow.tenant_id == tenant_id,
         %{} = version <- current_working_version(flow.id) do
      render(flow, version)
    else
      _ -> nil
    end
  rescue
    e ->
      Logger.warning("flow snapshot failed: #{Exception.message(e)}")
      nil
  end

  # The version the AI and the editor both work on: the latest draft,
  # or the latest version of any status when no draft exists.
  defp current_working_version(flow_id) do
    versions = Flows.list_versions(flow_id)

    case Enum.filter(versions, &(&1.status == "draft")) do
      [] -> List.last(versions)
      drafts -> Enum.max_by(drafts, & &1.version_number)
    end
  end

  defp render(flow, version) do
    graph = version.graph || %{"nodes" => [], "edges" => []}
    nodes = Map.get(graph, "nodes", [])
    edges = Map.get(graph, "edges", [])
    include_configs? = length(nodes) <= @config_node_limit

    config_note =
      if include_configs? do
        ""
      else
        "\n(config-ები არ არის ნაჩვენები — დეტალებისთვის გამოიყენე get_flow_graph)"
      end

    """

    ## მიმდინარე ფლოუ — მდგომარეობა ბაზაში

    Flow: #{flow.name} (id: #{flow.id}, status: #{flow.status})
    Version: #{version.version_number} (#{version.status})
    Nodes (#{length(nodes)}):
    #{render_nodes(nodes, include_configs?)}
    Edges (#{length(edges)}):
    #{render_edges(edges)}#{config_note}

    ეს არის გრაფის მიმდინარე მდგომარეობა — შესაძლოა ოპერატორმა ხელით შეცვალა
    წინა მესიჯის შემდეგ. ენდე ამ სექციას და არა საუბრის ისტორიაში არსებულ
    ძველ ვერსიებს.
    """
  end

  defp render_nodes([], _include_configs?), do: "  (ცარიელი)"

  defp render_nodes(nodes, include_configs?) do
    Enum.map_join(nodes, "\n", fn node ->
      base = "  - #{node["id"]} (#{node["type"]})"
      config = node["config"] || %{}

      if include_configs? and config != %{} do
        base <> " config: " <> truncate(Jason.encode!(config))
      else
        base
      end
    end)
  end

  defp render_edges([]), do: "  (ცარიელი)"

  defp render_edges(edges) do
    Enum.map_join(edges, "\n", fn edge ->
      base = "  - #{edge["source"]} → #{edge["target"]}"
      if edge["branch"], do: base <> " [branch: #{edge["branch"]}]", else: base
    end)
  end

  defp truncate(str) when byte_size(str) > @max_config_chars do
    String.slice(str, 0, @max_config_chars) <> "…"
  end

  defp truncate(str), do: str
end
