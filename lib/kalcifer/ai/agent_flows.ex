defmodule Kalcifer.AI.AgentFlows do
  @moduledoc """
  Manages agent flow templates — the Flow definitions that the engine
  uses to orchestrate Kalcifer's cognitive work cycles.

  The simplest agent flow is:

      [webhook_entry] → [agent] → [exit]

  More complex flows (councils, multi-persona deliberation) will be
  added as additional templates.
  """

  alias Kalcifer.Flows
  alias Kalcifer.Flows.Flow
  alias Kalcifer.Repo

  import Ecto.Query

  @simple_flow_name "__agent_simple__"

  @doc """
  Returns `{flow, version}` for the simple agent flow, creating it if needed.
  The flow is created as active with a published version.
  """
  def ensure_simple_flow(tenant_id, opts \\ []) do
    case find_agent_flow(tenant_id, @simple_flow_name) do
      nil -> create_simple_flow(tenant_id, opts)
      flow -> load_active_version(flow)
    end
  end

  @doc """
  Returns true if a flow is an internal agent flow (name starts with `__agent_`).
  """
  def agent_flow?(name) when is_binary(name), do: String.starts_with?(name, "__agent_")
  def agent_flow?(_), do: false

  # --- Private ---

  defp find_agent_flow(tenant_id, name) do
    Flow
    |> where(tenant_id: ^tenant_id, name: ^name)
    |> where([f], f.status in ["active", "draft"])
    |> Repo.one()
  end

  defp create_simple_flow(tenant_id, opts) do
    system_prompt = Keyword.get(opts, :system_prompt)
    graph = simple_flow_graph(system_prompt)

    Repo.transaction(fn ->
      {:ok, flow} =
        Flows.create_flow(tenant_id, %{
          name: @simple_flow_name,
          description: "Internal: simple agent assistant flow"
        })

      {:ok, version} =
        Flows.create_version(flow, %{graph: graph})

      {:ok, version} = Flows.publish_version(version)

      flow =
        flow
        |> Flow.status_changeset("active")
        |> Repo.update!()
        |> Flow.active_version_changeset(version.id)
        |> Repo.update!()

      {flow, version}
    end)
  end

  defp load_active_version(%Flow{active_version_id: nil} = _flow) do
    # Flow exists but has no active version — shouldn't happen, but handle gracefully
    {:error, :no_active_version}
  end

  defp load_active_version(%Flow{} = flow) do
    version = Repo.get(Kalcifer.Flows.FlowVersion, flow.active_version_id)

    if version do
      {:ok, {flow, version}}
    else
      {:error, :no_active_version}
    end
  end

  defp simple_flow_graph(system_prompt) do
    agent_config =
      %{"prompt" => "{{_initial_message}}", "include_context" => false}
      |> maybe_put("system", system_prompt)

    %{
      "nodes" => [
        %{"id" => "entry", "type" => "webhook_entry", "config" => %{}},
        %{"id" => "assistant", "type" => "agent", "config" => agent_config},
        %{"id" => "done", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry", "target" => "assistant"},
        %{"id" => "e2", "source" => "assistant", "target" => "done"}
      ]
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
