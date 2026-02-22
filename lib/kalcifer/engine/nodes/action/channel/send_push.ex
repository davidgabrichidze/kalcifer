defmodule Kalcifer.Engine.Nodes.Action.Channel.SendPush do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(_config, _context) do
    {:completed, %{sent: true, channel: "push"}}
  end

  @impl true
  def config_schema do
    %{"template_id" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :action
end
