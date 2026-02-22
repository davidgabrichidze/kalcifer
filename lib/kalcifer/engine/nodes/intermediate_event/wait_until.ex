defmodule Kalcifer.Engine.Nodes.IntermediateEvent.WaitUntil do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:waiting, %{until: config["datetime"]}}
  end

  @impl true
  def resume(_config, _context, _trigger) do
    {:completed, %{waited: true}}
  end

  @impl true
  def config_schema do
    %{"datetime" => %{"type" => "string", "format" => "datetime", "required" => true}}
  end

  @impl true
  def category, do: :intermediate_event
end
