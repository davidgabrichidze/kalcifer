defmodule Kalcifer.Engine.EventRouter do
  @moduledoc false

  alias Kalcifer.Engine.Persistence.InstanceStore

  def route_event(tenant_id, customer_id, event_type, event_data \\ %{}) do
    tenant_id
    |> InstanceStore.list_waiting_for_customer(customer_id)
    |> Enum.filter(&matches_event?(&1, event_type))
    |> Enum.map(&resume_instance(&1, event_data))
  end

  defp matches_event?(instance, event_type) do
    instance.context["_waiting_event_type"] == event_type
  end

  defp resume_instance(instance, event_data) do
    node_id = instance.context["_waiting_node_id"]
    via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance.id}}

    case GenServer.whereis(via) do
      nil ->
        {:not_alive, instance.id}

      _pid ->
        GenServer.cast(via, {:resume, node_id, event_data})
        {:ok, instance.id}
    end
  end
end
