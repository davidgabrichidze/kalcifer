defmodule Kalcifer.Engine.Nodes.Wait.WaitForEvent do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:waiting, %{event_type: config["event_type"]}}
  end

  @impl true
  def resume(_config, _context, :timeout) do
    {:branched, "timed_out", %{timed_out: true}}
  end

  def resume(_config, _context, trigger) do
    {:branched, "event_received", %{trigger: trigger}}
  end

  @impl true
  def config_schema do
    %{
      "event_type" => %{"type" => "string", "required" => true},
      "timeout" => %{"type" => "string", "required" => true}
    }
  end

  @impl true
  def category, do: :wait
end
