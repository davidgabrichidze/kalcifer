defmodule Kalcifer.Engine.Nodes.Action.Channel.CallWebhook do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Channels.ChannelSender

  @impl true
  def execute(config, context) do
    if context["_dry_run"] do
      {:completed,
       %{
         dry_run: true,
         would_call: %{
           channel: "webhook",
           url: config["url"]
         }
       }}
    else
      ChannelSender.send(:webhook, config, context)
    end
  end

  @impl true
  def config_schema do
    %{"url" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :action
end
