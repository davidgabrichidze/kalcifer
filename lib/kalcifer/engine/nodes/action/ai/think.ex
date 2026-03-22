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
      messages = build_messages(prompt, config, context)

      opts =
        case config["system"] do
          nil -> []
          sys -> [system: sys]
        end

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
      "include_context" => %{"type" => "boolean", "default" => true}
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

  defp build_messages(prompt, config, context) do
    include_ctx = Map.get(config, "include_context", true)

    content =
      if include_ctx do
        ctx_summary = summarize_context(context)
        "#{prompt}\n\nContext:\n#{ctx_summary}"
      else
        prompt
      end

    [%{role: "user", content: content}]
  end

  defp summarize_context(context) do
    # Include accumulated results from previous nodes, skip system fields
    context
    |> Map.get("accumulated", %{})
    |> Enum.map(fn {node_id, result} ->
      "#{node_id}: #{inspect(result, limit: 200)}"
    end)
    |> Enum.join("\n")
    |> case do
      "" -> "(no previous results)"
      summary -> summary
    end
  end
end
