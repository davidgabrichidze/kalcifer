defmodule Kalcifer.Engine.Nodes.EndEvent.JourneyExit do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(_config, _context) do
    {:completed, %{exit: true}}
  end

  @impl true
  def config_schema, do: %{}

  @impl true
  def category, do: :end_event
end
