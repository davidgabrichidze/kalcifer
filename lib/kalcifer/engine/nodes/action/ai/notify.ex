defmodule Kalcifer.Engine.Nodes.Action.AI.Notify do
  @moduledoc """
  Operator notification node — sends a message back to the operator
  who initiated the flow.

  Currently stores the notification in the flow context (pull model).
  When WebSocket support is added, this will push in real-time.

  ## Config

    - `message` — Static message template (optional)
    - `summarize` — If true, asks AI to summarize accumulated context (default: false)
    - `channel` — Notification channel: "chat" | "email" | "slack" (default: "chat")

  ## Result

  Returns `%{notified: true, message: "...", channel: "..."}`.
  """

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.AI.Client

  require Logger

  @impl true
  def execute(config, context) do
    channel = config["channel"] || "chat"

    message =
      cond do
        context["_dry_run"] ->
          "[dry run] Would notify: #{config["message"] || "flow completed"}"

        config["summarize"] == true ->
          summarize_with_ai(context)

        is_binary(config["message"]) ->
          interpolate_message(config["message"], context)

        true ->
          "ფლოუ დასრულდა."
      end

    # Broadcast via PubSub for real-time delivery
    tenant_id = context["_tenant_id"]
    instance_id = context["_instance_id"]

    unless context["_dry_run"] do
      Phoenix.PubSub.broadcast(
        Kalcifer.PubSub,
        "operator:#{tenant_id}",
        {:ai_notification, %{instance_id: instance_id, message: message, channel: channel}}
      )

      Logger.info("AI notification sent: tenant=#{tenant_id} channel=#{channel}")
    end

    {:completed,
     %{
       notified: true,
       message: message,
       channel: channel,
       instance_id: instance_id
     }}
  end

  @impl true
  def config_schema do
    %{
      "message" => %{"type" => "string"},
      "summarize" => %{"type" => "boolean", "default" => false},
      "channel" => %{
        "type" => "string",
        "enum" => ["chat", "email", "slack"],
        "default" => "chat"
      }
    }
  end

  @impl true
  def category, do: :action

  defp summarize_with_ai(context) do
    accumulated = Map.get(context, "accumulated", %{})

    prompt = """
    Summarize the following flow execution results in 2-3 sentences.
    Be concise and human-friendly. Speak Georgian if the content is Georgian.

    Results:
    #{inspect(accumulated, limit: 2000, pretty: true)}
    """

    case Client.chat([%{role: "user", content: prompt}]) do
      {:ok, summary} -> summary
      {:error, _} -> "ფლოუ დასრულდა. შედეგების ნახვა შეგიძლია დეტალებში."
    end
  end

  defp interpolate_message(template, context) do
    # Simple {{key}} interpolation from accumulated context
    Regex.replace(~r/\{\{(\w+)\}\}/, template, fn _full, key ->
      context
      |> Map.get("accumulated", %{})
      |> get_nested_value(key)
      |> to_string()
    end)
  end

  defp get_nested_value(map, key) when is_map(map) do
    case Map.get(map, key) do
      nil ->
        # Try to find in nested node results
        Enum.find_value(map, key, fn {_node_id, result} ->
          if is_map(result), do: Map.get(result, key)
        end)

      value ->
        value
    end
  end

  defp get_nested_value(_, key), do: "{{#{key}}}"
end
