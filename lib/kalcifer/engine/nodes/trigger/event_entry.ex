defmodule Kalcifer.Engine.Nodes.Trigger.EventEntry do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:completed, %{event_type: config["event_type"]}}
  end

  @impl true
  def config_schema do
    %{"event_type" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :trigger
end
