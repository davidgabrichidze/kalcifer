defmodule Kalcifer.Engine.Nodes.Data.UpdateProfile do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:completed, %{updated: true, fields: config["fields"] || %{}}}
  end

  @impl true
  def config_schema do
    %{"fields" => %{"type" => "object", "required" => true}}
  end

  @impl true
  def category, do: :task
end
