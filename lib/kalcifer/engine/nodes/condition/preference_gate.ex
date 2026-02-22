defmodule Kalcifer.Engine.Nodes.Condition.PreferenceGate do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, context) do
    channel = config["channel"]
    preferences = context["preferences"] || %{}
    opted_in = Map.get(preferences, channel, true)

    if opted_in do
      {:branched, "true", %{opted_in: true, channel: channel}}
    else
      {:branched, "false", %{opted_in: false, channel: channel}}
    end
  end

  @impl true
  def config_schema do
    %{"channel" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :condition
end
