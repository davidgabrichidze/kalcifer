defmodule Kalcifer.Engine.Nodes.Action.Channel.CallWebhook do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Channels.ChannelSender

  @impl true
  def execute(config, context) do
    ChannelSender.send(:webhook, config, context)
  end

  @impl true
  def config_schema do
    %{"url" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :action
end
