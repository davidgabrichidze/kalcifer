defmodule Kalcifer.Engine.Nodes.Task.Data.CustomCode do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  # Stub — real Lua sandbox execution deferred
  @impl true
  def execute(_config, _context) do
    {:completed, %{executed: true}}
  end

  @impl true
  def config_schema do
    %{"code" => %{"type" => "string", "required" => true, "language" => "lua"}}
  end

  @impl true
  def category, do: :task
end
