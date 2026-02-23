defmodule Kalcifer.Engine.Nodes.Action.Data.TrackConversion do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Analytics

  @impl true
  def execute(config, context) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      flow_id: context["_flow_id"],
      instance_id: context["_instance_id"],
      customer_id: context["_customer_id"],
      conversion_type: config["event_name"],
      value: config["revenue"],
      metadata: config["metadata"] || %{},
      converted_at: now
    }

    case Analytics.record_conversion(attrs) do
      {:ok, _conversion} ->
        {:completed,
         %{
           conversion_tracked: true,
           event_name: config["event_name"],
           revenue: config["revenue"]
         }}

      {:error, _changeset} ->
        {:completed,
         %{
           conversion_tracked: false,
           event_name: config["event_name"],
           reason: "record_failed"
         }}
    end
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
