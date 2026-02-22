defmodule Kalcifer.Engine.Nodes.Action.Channel.CallWebhook do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(_config, _context) do
    {:completed, %{sent: true, channel: "webhook"}}
  end

  @impl true
  def config_schema do
    %{"url" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :action
end
