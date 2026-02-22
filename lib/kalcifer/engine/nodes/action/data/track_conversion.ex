defmodule Kalcifer.Engine.Nodes.Action.Data.TrackConversion do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:completed,
     %{
       conversion_tracked: true,
       event_name: config["event_name"],
       revenue: config["revenue"]
     }}
  end

  @impl true
  def config_schema do
    %{
      "event_name" => %{"type" => "string", "required" => true},
      "revenue" => %{"type" => "number"}
    }
  end

  @impl true
  def category, do: :action
end
