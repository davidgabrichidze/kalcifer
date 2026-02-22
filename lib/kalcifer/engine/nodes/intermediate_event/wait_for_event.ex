defmodule Kalcifer.Engine.Nodes.IntermediateEvent.WaitForEvent do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:waiting, %{event_type: config["event_type"], timeout: config["timeout"]}}
  end

  @impl true
  def resume(_config, _context, trigger) do
    case trigger do
      :timeout ->
        {:branched, "timed_out", %{timed_out: true}}

      %{event_type: _} = event ->
        {:branched, "event_received", %{event: event}}

      _ ->
        {:branched, "event_received", %{trigger: trigger}}
    end
  end

  @impl true
  def config_schema do
    %{
      "event_type" => %{"type" => "string", "required" => true},
      "timeout" => %{"type" => "string", "example" => "3d"}
    }
  end

  @impl true
  def category, do: :intermediate_event
end
