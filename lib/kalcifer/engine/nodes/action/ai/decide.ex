defmodule Kalcifer.Engine.Nodes.Action.AI.Decide do
  @moduledoc """
  AI decision node — uses Claude to make a branching decision
  based on flow context.

  Unlike a static `condition` node with hardcoded rules, this node
  sends context to the AI and asks it to choose a branch. The AI
  returns a branch key that maps to graph edges.

  ## Config

    - `question` — What the AI should decide (required)
    - `branches` — List of possible branch keys, e.g. `["approve", "reject", "escalate"]` (required)
    - `criteria` — Optional guidance for the decision

  ## Result

  Returns `{:branched, chosen_branch, %{reasoning: "..."}}`.
  """

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Engine.Nodes.Action.AI.Helpers

  defp client, do: Application.get_env(:kalcifer, :ai_client, Kalcifer.AI.Client)

  @impl true
  def execute(config, context) do
    branches = config["branches"] || ["true", "false"]

    if context["_dry_run"] do
      {:branched, List.first(branches),
       %{
         dry_run: true,
         question: config["question"],
         chose: List.first(branches),
         reasoning: "[dry run — picked first branch]"
       }}
    else
      question = config["question"] || "Should we proceed?"
      criteria = config["criteria"] || ""

      prompt = """
      You must make a decision. Answer with ONLY one of these exact values: #{Enum.join(branches, ", ")}

      Question: #{question}
      #{if criteria != "", do: "Criteria: #{criteria}", else: ""}

      Context from previous steps:
      #{Helpers.summarize_context(context)}

      Reply with ONLY the chosen value, nothing else.
      """

      opts = if config["model"], do: [model: config["model"]], else: []

      case client().chat([%{role: "user", content: prompt}], opts) do
        {:ok, response} ->
          chosen = parse_branch(response, branches)

          {:branched, chosen,
           %{
             question: question,
             chose: chosen,
             raw_response: response,
             reasoning: String.trim(response)
           }}

        {:error, reason} ->
          {:failed, %{reason: :ai_decision_error, details: inspect(reason)}}
      end
    end
  end

  @impl true
  def config_schema do
    %{
      "question" => %{"type" => "string", "required" => true},
      "branches" => %{"type" => "array", "items" => %{"type" => "string"}, "required" => true},
      "criteria" => %{"type" => "string"},
      "model" => %{
        "type" => "string",
        "description" => "Override AI model for this node"
      }
    }
  end

  @impl true
  def category, do: :condition

  @impl true
  def validate(config) do
    errors =
      []
      |> maybe_add(
        !is_binary(config["question"]) or config["question"] == "",
        "question is required"
      )
      |> maybe_add(
        !is_list(config["branches"]) or length(config["branches"]) < 2,
        "branches must have at least 2 options"
      )

    case errors do
      [] -> :ok
      errs -> {:error, errs}
    end
  end

  defp parse_branch(response, branches) do
    cleaned = response |> String.trim() |> String.downcase()

    Enum.find(branches, List.first(branches), fn branch ->
      String.downcase(branch) == cleaned
    end)
  end

  defp maybe_add(errors, true, msg), do: [msg | errors]
  defp maybe_add(errors, false, _msg), do: errors
end
