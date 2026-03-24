defmodule Kalcifer.Engine.Nodes.Action.Channel.SendEmail do
  @moduledoc """
  Send email action node.

  Config:
    - template_id: external template ID (e.g. SendGrid template)
    - subject: email subject line (supports {{variable}} interpolation)
    - body: email body in HTML or plain text (supports {{variable}} interpolation)
    - from_name: sender display name (optional)
    - reply_to: reply-to address (optional)

  Either template_id OR subject+body should be provided.
  Variables use {{context_key}} syntax and are interpolated from flow context.
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
           channel: "email",
           template_id: config["template_id"],
           subject: interpolate(config["subject"], context),
           body_preview: interpolate(config["body"], context) |> truncate(200),
           recipient: context["_email"] || context["_customer_id"]
         }
       }}
    else
      # Interpolate subject and body before sending
      enriched_config =
        config
        |> maybe_interpolate("subject", context)
        |> maybe_interpolate("body", context)

      ChannelSender.send(:email, enriched_config, context)
    end
  end

  @impl true
  def config_schema do
    %{
      "template_id" => %{
        "type" => "string",
        "description" => "External template ID (SendGrid, etc.)"
      },
      "subject" => %{
        "type" => "string",
        "description" => "Email subject. Supports {{variable}} interpolation."
      },
      "body" => %{
        "type" => "string",
        "description" => "Email body (HTML or text). Supports {{variable}} interpolation."
      },
      "from_name" => %{
        "type" => "string",
        "description" => "Sender display name"
      },
      "reply_to" => %{
        "type" => "string",
        "description" => "Reply-to email address"
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

  defp truncate(nil, _), do: nil
  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "..."
end
