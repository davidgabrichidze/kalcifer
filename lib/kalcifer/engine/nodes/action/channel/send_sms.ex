defmodule Kalcifer.Engine.Nodes.Action.Channel.SendSms do
  @moduledoc """
  Send SMS action node.

  Config:
    - body: SMS text (supports {{variable}} interpolation, max 160 chars recommended)
    - sender_id: sender ID or phone number (optional)
    - template_id: external template ID (optional, alternative to body)
  """

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Channels.ChannelSender

  @impl true
  def execute(config, context) do
    if context["_dry_run"] do
      {:completed,
       %{
         dry_run: true,
         would_send: %{
           channel: "sms",
           body: interpolate(config["body"], context),
           char_count: String.length(interpolate(config["body"], context) || ""),
           recipient: context["_phone"] || context["_customer_id"]
         }
       }}
    else
      enriched_config =
        config
        |> maybe_interpolate("body", context)

      ChannelSender.send(:sms, enriched_config, context)
    end
  end

  @impl true
  def config_schema do
    %{
      "body" => %{
        "type" => "string",
        "description" => "SMS text. Supports {{variable}} interpolation. Max 160 chars."
      },
      "sender_id" => %{
        "type" => "string",
        "description" => "Sender ID or phone number"
      },
      "template_id" => %{
        "type" => "string",
        "description" => "External template ID (alternative to body)"
      }
    }
  end

  @impl true
  def category, do: :action

  defp interpolate(nil, _context), do: nil

  defp interpolate(text, context) when is_binary(text) do
    Regex.replace(~r/\{\{(\w+)\}\}/, text, fn _, key ->
      to_string(Map.get(context, key, "{{#{key}}}"))
    end)
  end

  defp maybe_interpolate(config, key, context) do
    case config[key] do
      nil -> config
      value -> Map.put(config, key, interpolate(value, context))
    end
  end
end
