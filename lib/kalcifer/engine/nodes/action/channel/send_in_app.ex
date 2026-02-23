defmodule Kalcifer.Engine.Nodes.Action.Channel.SendInApp do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Channels.ChannelSender

  @impl true
  def execute(config, context) do
    ChannelSender.send(:in_app, config, context)
  end

  @impl true
  def config_schema do
    %{
      "template_id" => %{"type" => "string", "required" => true},
      "placement" => %{"type" => "string"},
      "expiry" => %{"type" => "string"}
    }
  end

  @impl true
  def category, do: :action
end
