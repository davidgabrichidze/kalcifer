defmodule Kalcifer.Engine.Nodes.End.Exit do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(_config, _context) do
    {:completed, %{exit: true}}
  end

  @impl true
  def config_schema, do: %{}

  @impl true
  def category, do: :end
end
