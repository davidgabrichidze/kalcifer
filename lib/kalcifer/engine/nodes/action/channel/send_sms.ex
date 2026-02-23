defmodule Kalcifer.Engine.Nodes.Action.Channel.SendSms do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Channels.ChannelSender

  @impl true
  def execute(config, context) do
    ChannelSender.send(:sms, config, context)
  end

  @impl true
  def config_schema do
    %{"template_id" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :action
end
