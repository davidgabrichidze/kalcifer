defmodule Kalcifer.Engine.Nodes.Condition.FrequencyCap do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Engine.FrequencyCapHelpers
  alias Kalcifer.Engine.Persistence.StepStore

  @impl true
  def execute(config, context) do
    with {:ok, customer_id} <- fetch_customer_id(context),
         {:ok, max_messages, node_types, since} <- parse_config(config) do
      count = StepStore.count_channel_steps_for_customer(customer_id, node_types, since)

      if count >= max_messages do
        {:branched, "capped", %{capped: true, count: count, max: max_messages}}
      else
        {:branched, "allowed", %{capped: false, count: count, max: max_messages}}
      end
    else
      {:error, reason} ->
        {:branched, "allowed", %{capped: false, error: reason}}
    end
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

  defp fetch_customer_id(context) do
    case Map.get(context, "_customer_id") do
      nil -> {:error, :missing_customer_id}
      id -> {:ok, id}
    end
  end

  defp parse_config(config) do
    max = config["max_messages"]
    raw_w = config["time_window"]
    ch = config["channel"] || "all"

    with true <- is_integer(max) and max > 0,
         {:ok, since} <- FrequencyCapHelpers.parse_time_window(raw_w),
         {:ok, types} <- FrequencyCapHelpers.resolve_channel_types(ch) do
      {:ok, max, types, since}
    else
      _ -> {:error, :invalid_config}
    end
  end
end
