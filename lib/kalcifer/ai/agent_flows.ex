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
  @council_flow_name "__agent_council__"

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

  @doc """
  Returns `{flow, version}` for the council flow (multi-persona deliberation).
  Graph: [entry] → [dreamer] → [realist] → [skeptic] → [synthesizer] → [agent] → [exit]
  """
  def ensure_council_flow(tenant_id, opts \\ []) do
    case find_agent_flow(tenant_id, @council_flow_name) do
      nil -> create_council_flow(tenant_id, opts)
      flow -> load_active_version(flow)
    end
  end

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

  defp create_council_flow(tenant_id, _opts) do
    graph = council_flow_graph()

    Repo.transaction(fn ->
      {:ok, flow} =
        Flows.create_flow(tenant_id, %{
          name: @council_flow_name,
          description: "Internal: council deliberation flow (dreamer/realist/skeptic)"
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

  defp council_flow_graph do
    %{
      "nodes" => [
        %{"id" => "entry", "type" => "webhook_entry", "config" => %{}},
        %{"id" => "dreamer", "type" => "ai_think", "config" => %{
          "prompt" => "You are the Dreamer — an optimistic, creative thinker.\n\nUser request: {{_initial_message}}\n\nGenerate bold, ambitious ideas. Think big. What would be the ideal outcome? What creative approaches could work? Don't worry about constraints yet.",
          "system" => "You are the Dreamer persona in a council deliberation. Be creative, optimistic, and visionary. Output your ideas clearly."
        }},
        %{"id" => "realist", "type" => "ai_think", "config" => %{
          "prompt" => "You are the Realist — a practical, grounded thinker.\n\nUser request: {{_initial_message}}\n\nThe Dreamer proposed:\n{{accumulated.dreamer.response}}\n\nEvaluate these ideas practically. What's feasible? What resources are needed? Create a realistic plan from the Dreamer's vision.",
          "system" => "You are the Realist persona in a council deliberation. Be practical and constructive. Build on the Dreamer's ideas with concrete steps."
        }},
        %{"id" => "skeptic", "type" => "ai_think", "config" => %{
          "prompt" => "You are the Skeptic — a critical, risk-aware thinker.\n\nUser request: {{_initial_message}}\n\nThe Dreamer proposed:\n{{accumulated.dreamer.response}}\n\nThe Realist's plan:\n{{accumulated.realist.response}}\n\nChallenge both perspectives. What could go wrong? What are the risks? What assumptions are being made? Be constructive but thorough.",
          "system" => "You are the Skeptic persona in a council deliberation. Identify risks and weak points constructively. Don't just criticize — suggest mitigations."
        }},
        %{"id" => "synthesizer", "type" => "ai_think", "config" => %{
          "prompt" => "You are the Synthesizer — you integrate all perspectives into a final recommendation.\n\nUser request: {{_initial_message}}\n\nDreamer's vision:\n{{accumulated.dreamer.response}}\n\nRealist's plan:\n{{accumulated.realist.response}}\n\nSkeptic's concerns:\n{{accumulated.skeptic.response}}\n\nCreate a balanced, actionable synthesis that takes the best from each perspective and addresses the concerns raised.",
          "system" => "You are the Synthesizer. Create a clear, balanced recommendation that integrates all perspectives. Be decisive."
        }},
        %{"id" => "executor", "type" => "agent", "config" => %{
          "prompt" => "Based on the council's deliberation, execute the recommended plan.\n\nFinal recommendation:\n{{accumulated.synthesizer.response}}\n\nOriginal request: {{_initial_message}}",
          "include_context" => false
        }},
        %{"id" => "done", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry", "target" => "dreamer"},
        %{"id" => "e2", "source" => "dreamer", "target" => "realist"},
        %{"id" => "e3", "source" => "realist", "target" => "skeptic"},
        %{"id" => "e4", "source" => "skeptic", "target" => "synthesizer"},
        %{"id" => "e5", "source" => "synthesizer", "target" => "executor"},
        %{"id" => "e6", "source" => "executor", "target" => "done"}
      ]
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
