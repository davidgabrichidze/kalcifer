defmodule Kalcifer.Engine.Nodes.Trigger.SegmentEntry do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:completed, %{segment_id: config["segment_id"]}}
  end

  @impl true
  def config_schema do
    %{"segment_id" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :trigger
end
