defmodule Kalcifer.Engine.Nodes.StartEvent.EventEntry do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:completed, %{event_type: config["event_type"]}}
  end

  @impl true
  def validate(config) do
    if is_binary(config["event_type"]) and config["event_type"] != "" do
      :ok
    else
      {:error, ["event_type is required"]}
    end
  end

  @impl true
  def config_schema do
    %{"event_type" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :start_event
end
