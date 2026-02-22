defmodule Kalcifer.Engine.Nodes.Logic.Wait do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:waiting, %{duration: config["duration"]}}
  end

  @impl true
  def resume(_config, _context, _trigger) do
    {:completed, %{waited: true}}
  end

  @impl true
  def config_schema do
    %{"duration" => %{"type" => "string", "required" => true, "example" => "3d"}}
  end

  @impl true
  def category, do: :intermediate_event
end
