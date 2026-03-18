defmodule Kalcifer.Engine.Nodes.Action.Channel.SendSms do
  @moduledoc false

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
           template_id: config["template_id"],
           recipient: context["_phone"] || context["_customer_id"]
         }
       }}
    else
      ChannelSender.send(:sms, config, context)
    end
  end

  @impl true
  def config_schema do
    %{"template_id" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :action
end
