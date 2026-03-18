defmodule Kalcifer.Engine.Nodes.Wait.Wait do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, context) do
    if context["_dry_run"] do
      {:completed, %{dry_run: true, skipped_wait: config["duration"], waited: true}}
    else
      {:waiting, %{duration: config["duration"]}}
    end
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
