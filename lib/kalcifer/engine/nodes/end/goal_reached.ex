defmodule Kalcifer.Engine.Nodes.End.GoalReached do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Analytics

  @impl true
  def execute(config, context) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Analytics.record_conversion(%{
      flow_id: context["_flow_id"],
      instance_id: context["_instance_id"],
      customer_id: context["_customer_id"],
      conversion_type: "goal:#{config["goal_name"]}",
      metadata: %{"goal_name" => config["goal_name"]},
      converted_at: now
    })

    {:completed, %{exit: true, goal: config["goal_name"]}}
  end

  @impl true
  def config_schema do
    %{"goal_name" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :end
end
