defmodule Kalcifer.Engine.Nodes.Exit.GoalReached do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:completed, %{exit: true, goal: config["goal_name"]}}
  end

  @impl true
  def config_schema do
    %{"goal_name" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :end_event
end
