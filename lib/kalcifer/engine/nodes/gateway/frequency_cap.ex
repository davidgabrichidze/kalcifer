defmodule Kalcifer.Engine.Nodes.Gateway.FrequencyCap do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  # Stub — real frequency cap checking deferred to later increment
  @impl true
  def execute(_config, _context) do
    {:branched, "allowed", %{capped: false}}
  end

  @impl true
  def config_schema do
    %{
      "max_sends" => %{"type" => "integer"},
      "period" => %{"type" => "string", "example" => "24h"}
    }
  end

  @impl true
  def category, do: :gateway
end
