defmodule Kalcifer.Engine.Nodes.Condition.CheckSegment do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, context) do
    segment_id = config["segment_id"]
    customer_segments = context["segments"] || []

    if segment_id in customer_segments do
      {:branched, "true", %{in_segment: true, segment_id: segment_id}}
    else
      {:branched, "false", %{in_segment: false, segment_id: segment_id}}
    end
  end

  @impl true
  def config_schema do
    %{"segment_id" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :condition
end
