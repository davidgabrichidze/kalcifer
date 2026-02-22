defmodule Kalcifer.Engine.Nodes.Condition.FrequencyCap do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(_config, _context) do
    # Stub — real frequency cap checking deferred
    {:branched, "allowed", %{capped: false}}
  end

  @impl true
  def config_schema do
    %{
      "max_messages" => %{"type" => "integer"},
      "time_window" => %{"type" => "string"},
      "channel" => %{"type" => "string"}
    }
  end

  @impl true
  def category, do: :condition
end
