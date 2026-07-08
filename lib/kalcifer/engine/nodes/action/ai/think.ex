defmodule Kalcifer.Engine.Nodes.Action.AI.Think do
  @moduledoc """
  AI thinking node — sends a prompt to Claude with flow context
  and accumulates the result.

  This is the core building block for AI-powered flows. When Kalcifer
  uses its own engine for "thinking", each reasoning step is a Think node.

  ## Config

    - `prompt` — The instruction/question for the AI (required)
    - `system` — Optional system prompt override
    - `include_context` — Whether to include accumulated context (default: true)

  ## Result

  Returns `%{response: "...", model: "..."}` in context.
  """

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Engine.Nodes.Action.AI.Helpers

  defp client, do: Application.get_env(:kalcifer, :ai_client, Kalcifer.AI.Client)

  @impl true
  def execute(config, context) do
    if context["_dry_run"] do
      {:completed,
       %{
         dry_run: true,
         would_think_about: config["prompt"],
         response: "[dry run — skipped AI call]"
       }}
    else
      prompt = config["prompt"] || "Analyze the current context and provide insights."

      # Build messages with context if requested
      messages = Helpers.build_messages(prompt, config, context)

      opts =
        case config["system"] do
          nil -> []
          sys -> [system: sys]
        end

      # Per-node model override
      opts = if config["model"], do: [{:model, config["model"]} | opts], else: opts

      case client().chat(messages, opts) do
        {:ok, response} ->
          {:completed, %{response: response, prompt: prompt}}

        {:error, reason} ->
          {:failed, %{reason: :ai_error, details: inspect(reason)}}
      end
    end
  end

  @impl true
  def config_schema do
    %{
      "prompt" => %{"type" => "string", "required" => true},
      "system" => %{"type" => "string"},
      "include_context" => %{"type" => "boolean", "default" => true},
      "model" => %{
        "type" => "string",
        "description" => "Override AI model for this node (e.g. 'gpt-5.5', 'claude-sonnet-5')"
      }
    }
  end

  @impl true
  def category, do: :action

  @impl true
  def validate(config) do
    if is_binary(config["prompt"]) and String.length(config["prompt"]) > 0 do
      :ok
    else
      {:error, ["prompt is required and must be a non-empty string"]}
    end
  end
end
