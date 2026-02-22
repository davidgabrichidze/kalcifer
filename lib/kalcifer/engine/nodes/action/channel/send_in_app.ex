defmodule Kalcifer.Engine.Nodes.Action.Channel.SendInApp do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(_config, _context) do
    {:completed, %{sent: true, channel: "in_app"}}
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
