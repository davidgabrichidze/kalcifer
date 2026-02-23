defmodule Kalcifer.Engine.FlowTrigger do
  @moduledoc false

  alias Kalcifer.Engine.FrequencyCapHelpers
  alias Kalcifer.Engine.Persistence.InstanceStore
  alias Kalcifer.Engine.Persistence.StepStore
  alias Kalcifer.Flows
  alias Kalcifer.Flows.FlowVersion
  alias Kalcifer.Repo

  def trigger(flow_id, customer_id, initial_context \\ %{}) do
    with {:ok, flow} <- fetch_active_flow(flow_id),
         {:ok, version} <- fetch_active_version(flow),
         :ok <- check_not_in_flow(flow_id, customer_id),
         :ok <- check_flow_frequency_cap(flow, customer_id) do
      instance_id = Ecto.UUID.generate()

      args = %{
        instance_id: instance_id,
        flow_id: flow.id,
        customer_id: customer_id,
        tenant_id: flow.tenant_id,
        version_number: version.version_number,
        graph: version.graph,
        initial_context: initial_context
      }

      case DynamicSupervisor.start_child(
             Kalcifer.Engine.FlowSupervisor,
             {Kalcifer.Engine.FlowServer, args}
           ) do
        {:ok, _pid} -> {:ok, instance_id}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fetch_active_flow(flow_id) do
    case Flows.get_flow(flow_id) do
      %{status: "active"} = flow -> {:ok, flow}
      %{} -> {:error, :flow_not_active}
      nil -> {:error, :not_found}
    end
  end

  defp check_not_in_flow(flow_id, customer_id) do
    if InstanceStore.customer_active_in_flow?(flow_id, customer_id) do
      {:error, :already_in_flow}
    else
      :ok
    end
  end

  defp check_flow_frequency_cap(%{frequency_cap: cap}, _customer_id)
       when map_size(cap) == 0 do
    :ok
  end

  defp check_flow_frequency_cap(%{frequency_cap: cap}, customer_id) do
    max = Map.get(cap, "max_messages")
    raw_w = Map.get(cap, "time_window")
    channel = Map.get(cap, "channel", "all")

    with true <- is_integer(max) and max > 0,
         {:ok, since} <- FrequencyCapHelpers.parse_time_window(raw_w),
         {:ok, types} <- FrequencyCapHelpers.resolve_channel_types(channel) do
      count = StepStore.count_channel_steps_for_customer(customer_id, types, since)

      if count >= max do
        {:error, :frequency_cap_exceeded}
      else
        :ok
      end
    else
      _ -> :ok
    end
  end

  defp fetch_active_version(%{active_version_id: nil}), do: {:error, :no_active_version}

  defp fetch_active_version(flow) do
    case Repo.get(FlowVersion, flow.active_version_id) do
      nil -> {:error, :no_active_version}
      version -> {:ok, version}
    end
  end
end
