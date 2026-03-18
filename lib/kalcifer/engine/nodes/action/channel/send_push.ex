defmodule Kalcifer.Engine.Nodes.Action.Channel.SendPush do
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
           channel: "push",
           template_id: config["template_id"],
           recipient: context["_customer_id"]
         }
       }}
    else
      ChannelSender.send(:push, config, context)
    end
  end

  @impl true
  def config_schema do
    %{"template_id" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :action
end
