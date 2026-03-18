defmodule Kalcifer.Engine.Nodes.Wait.WaitForEvent do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, context) do
    if context["_dry_run"] do
      {:branched, "event_received",
       %{dry_run: true, skipped_wait_for: config["event_type"], trigger: %{}}}
    else
      {:waiting, %{event_type: config["event_type"]}}
    end
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
