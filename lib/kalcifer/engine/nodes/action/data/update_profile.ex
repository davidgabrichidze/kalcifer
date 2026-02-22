defmodule Kalcifer.Engine.Nodes.Action.Data.UpdateProfile do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(_config, _context) do
    {:completed, %{updated: true}}
  end

  @impl true
  def config_schema do
    %{"fields" => %{"type" => "map", "required" => true}}
  end

  @impl true
  def category, do: :action
end
