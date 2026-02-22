defmodule Kalcifer.Engine.Nodes.Entry.SegmentEntry do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:completed, %{segment_id: config["segment_id"]}}
  end

  @impl true
  def validate(config) do
    if is_binary(config["segment_id"]) and config["segment_id"] != "" do
      :ok
    else
      {:error, ["segment_id is required"]}
    end
  end

  @impl true
  def config_schema do
    %{"segment_id" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :start_event
end
