defmodule Kalcifer.Engine.Nodes.Action.AI.Agent do
  @moduledoc """
  Agentic AI node — multi-round chat with tool use.

  Unlike `ai_think` (single LLM call), this node runs a full agentic loop:
  the AI can call tools, evaluate results, and iterate up to `max_rounds`.

  Progress (text deltas, tool events) is broadcast via PubSub so that
  listeners (e.g. ChatController) can stream them in real time.

  ## Config

    - `system`     — system prompt / persona role (optional)
    - `prompt`     — task prompt, supports `{{path}}` interpolation (required)
    - `model`      — model override (optional)
    - `tools`      — tool name whitelist, e.g. `["create_flow"]` (optional; nil = all)
    - `max_rounds` — tool round limit (optional, default: 20)

  ## Result

  Returns `%{response: "...", tool_calls: [...], rounds: n}`.
  """

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.AI.Tools
  alias Kalcifer.Engine.EventBroadcaster
  alias Kalcifer.Engine.Nodes.Action.AI.Helpers

  defp client, do: Application.get_env(:kalcifer, :ai_client, Kalcifer.AI.Client)

  @default_max_rounds 20

  @impl true
  def execute(config, context) do
    if context["_dry_run"] do
      {:completed,
       %{
         dry_run: true,
         would_execute: config["prompt"],
         response: "[dry run — skipped agent loop]"
       }}
    else
      run_agent(config, context)
    end
  end

  @impl true
  def config_schema do
    %{
      "prompt" => %{"type" => "string", "required" => true},
      "system" => %{"type" => "string"},
      "model" => %{"type" => "string"},
      "tools" => %{"type" => "array", "items" => %{"type" => "string"}},
      "max_rounds" => %{"type" => "integer", "default" => @default_max_rounds},
      "include_context" => %{"type" => "boolean", "default" => true}
    }
  end

  @impl true
  def category, do: :action

  @impl true
  def validate(config) do
    if is_binary(config["prompt"]) and config["prompt"] != "" do
      :ok
    else
      {:error, ["prompt is required and must be a non-empty string"]}
    end
  end

  # --- Private ---

  defp run_agent(config, context) do
    instance_id = context["_instance_id"]
    tenant_id = context["_tenant_id"]
    prompt = Helpers.interpolate(config["prompt"], context)

    # Build messages: either from context (full conversation) or from prompt
    messages = build_agent_messages(prompt, config, context)

    # System prompt: config overrides context fallback
    system = config["system"] || context["_system_prompt"]
    opts = if system, do: [system: system], else: []
    opts = maybe_add_model(opts, config)
    # Merge tenant AI opts (model, api_key, provider) from context
    opts = merge_tenant_opts(opts, context)

    # Tool definitions — filtered by whitelist if provided
    tool_defs = filter_tools(config["tools"])

    # Tool executor
    tool_ctx = %{conversation_id: context["_conversation_id"]}

    tool_executor = fn name, input ->
      Tools.execute(name, input, tenant_id, tool_ctx)
    end

    # Callback — broadcasts progress via PubSub
    tool_calls = :ets.new(:agent_tool_calls, [:set, :private])
    callback = build_callback(instance_id, tool_calls)

    # Max rounds
    max_rounds = config["max_rounds"] || @default_max_rounds
    opts = [{:max_tool_rounds, max_rounds} | opts]

    case client().chat_with_tools(messages, tool_defs, tool_executor, callback, opts) do
      {:ok, full_text} ->
        calls = :ets.tab2list(tool_calls) |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
        :ets.delete(tool_calls)

        EventBroadcaster.broadcast_agent_done(instance_id, full_text)

        {:completed,
         %{
           response: full_text,
           tool_calls: calls,
           rounds: length(calls)
         }}

      {:error, reason} ->
        :ets.delete(tool_calls)
        {:failed, %{reason: :agent_error, details: inspect(reason)}}
    end
  end

  defp build_agent_messages(prompt, config, context) do
    # If _messages is in context (from ChatController), use the full conversation
    case context["_messages"] do
      messages when is_list(messages) and messages != [] ->
        messages

      _ ->
        Helpers.build_messages(prompt, config, context)
    end
  end

  defp build_callback(instance_id, tool_calls) do
    counter = :counters.new(1, [:atomics])

    fn
      {:text_delta, text} ->
        EventBroadcaster.broadcast_agent_text_delta(instance_id, text)

      {:tool_use, _id, name, input} ->
        EventBroadcaster.broadcast_agent_tool_start(instance_id, name, input)

      {:tool_result, name, result} ->
        idx = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)
        :ets.insert(tool_calls, {idx, %{tool: name, result: result}})
        EventBroadcaster.broadcast_agent_tool_done(instance_id, name, result)

      {:done, _full_text} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp filter_tools(nil), do: Tools.definitions()

  defp filter_tools(whitelist) when is_list(whitelist) do
    Tools.definitions()
    |> Enum.filter(fn tool -> tool.name in whitelist end)
  end

  defp maybe_add_model(opts, %{"model" => model}) when is_binary(model),
    do: [{:model, model} | opts]

  defp maybe_add_model(opts, _config), do: opts

  defp merge_tenant_opts(opts, context) do
    case context["_ai_opts"] do
      ai_opts when is_list(ai_opts) -> opts ++ ai_opts
      _ -> opts
    end
  end
end
