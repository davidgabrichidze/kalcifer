defmodule Kalcifer.Engine.Nodes.Wait.WaitUntil do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:waiting, %{until: config["datetime"]}}
  end

  @impl true
  def resume(_config, _context, :timer_expired) do
    {:completed, %{waited: true}}
  end

  def resume(_config, _context, _trigger) do
    {:failed, :unexpected_trigger}
  end

  @impl true
  def config_schema do
    %{"datetime" => %{"type" => "string", "required" => true, "format" => "iso8601"}}
  end

  @impl true
  def category, do: :wait
end
