defmodule Kalcifer.Engine.Nodes.Action.AI.FlowRouter do
  @moduledoc """
  AI-powered dynamic flow router — selects which sub-flow to execute
  based on context analysis.

  Combines ai_decide (AI picks a route) + sub_flow (executes the chosen flow).

  Config:
    - question: what the AI should decide (e.g. "Is this a simple or complex request?")
    - routes: map of route_name → flow_id
      Example: %{"simple" => "flow-uuid-1", "complex" => "flow-uuid-2"}
    - criteria: optional guidance for the AI
    - context_mapping: optional parent→child context key mapping

  Result: branches to the chosen route, then the graph edge leads to sub_flow or next step.
  """

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Engine.Nodes.Action.AI.Helpers

  defp client, do: Application.get_env(:kalcifer, :ai_client, Kalcifer.AI.Client)

  @impl true
  def execute(config, context) do
    routes = config["routes"] || %{}
    route_names = Map.keys(routes)

    if context["_dry_run"] do
      first_route = List.first(route_names) || "default"

      {:branched, first_route,
       %{
         dry_run: true,
         question: config["question"],
         routes: routes,
         chose: first_route,
         flow_id: routes[first_route],
         reasoning: "[dry run — picked first route]"
       }}
    else
      execute_routing(config, context, routes, route_names)
    end
  end

  @impl true
  def config_schema do
    %{
      "question" => %{
        "type" => "string",
        "required" => true,
        "description" => "What the AI should decide to route"
      },
      "routes" => %{
        "type" => "object",
        "required" => true,
        "description" => "Map of route_name → flow_id (UUID)"
      },
      "criteria" => %{
        "type" => "string",
        "description" => "Optional guidance for the AI routing decision"
      },
      "context_mapping" => %{
        "type" => "object",
        "description" => "Map parent context keys to child context keys"
      }
    }
  end

  @impl true
  def validate(config) do
    errors = []

    errors =
      if is_binary(config["question"]) and config["question"] != "" do
        errors
      else
        ["question is required" | errors]
      end

    errors =
      if is_map(config["routes"]) and map_size(config["routes"]) >= 2 do
        errors
      else
        ["routes must have at least 2 entries" | errors]
      end

    case errors do
      [] -> :ok
      errs -> {:error, Enum.reverse(errs)}
    end
  end

  @impl true
  def category, do: :condition

  # ── Private ──────────────────────────────────────────

  defp execute_routing(config, context, routes, route_names) do
    question = config["question"] || "Which route should we take?"
    criteria = config["criteria"] || ""

    prompt = """
    You are a flow router. Choose the best route based on the context.
    Answer with ONLY one of these exact values: #{Enum.join(route_names, ", ")}

    Question: #{question}
    #{if criteria != "", do: "Criteria: #{criteria}", else: ""}

    Routes available:
    #{Enum.map_join(route_names, "\n", fn name -> "- #{name}" end)}

    Context from previous steps:
    #{Helpers.summarize_context(context)}

    Reply with ONLY the chosen route name, nothing else.
    """

    opts = if config["model"], do: [model: config["model"]], else: []

    case client().chat([%{role: "user", content: prompt}], opts) do
      {:ok, response} ->
        chosen = parse_route(response, route_names)
        flow_id = routes[chosen]

        {:branched, chosen,
         %{
           question: question,
           chose: chosen,
           flow_id: flow_id,
           reasoning: String.trim(response),
           available_routes: route_names
         }}

      {:error, reason} ->
        {:failed, %{reason: :routing_error, details: inspect(reason)}}
    end
  end

  defp parse_route(response, route_names) do
    cleaned = response |> String.trim() |> String.downcase()

    Enum.find(route_names, List.first(route_names), fn name ->
      String.downcase(name) == cleaned
    end)
  end
end
