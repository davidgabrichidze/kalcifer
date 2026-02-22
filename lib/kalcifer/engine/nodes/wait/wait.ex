defmodule Kalcifer.Engine.Nodes.Wait.Wait do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:waiting, %{duration: config["duration"]}}
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
    %{"duration" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :wait
end
