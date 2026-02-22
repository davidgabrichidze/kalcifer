defmodule Kalcifer.Engine.Nodes.Task.Data.AddTag do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:completed, %{tagged: true, tag: config["tag"]}}
  end

  @impl true
  def config_schema do
    %{"tag" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :task
end
