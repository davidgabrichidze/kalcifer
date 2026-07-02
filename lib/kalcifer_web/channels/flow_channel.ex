defmodule KalciferWeb.FlowChannel do
  @moduledoc """
  Phoenix Channel for real-time flow/instance/tenant events.

  Subscribes to PubSub on join and pushes engine events to clients.
  Topics: flow:{id}, tenant:{id}, instance:{id}
  """

  use Phoenix.Channel

  alias KalciferWeb.Presence

  @impl true
  def join("flow:" <> flow_id, params, socket) do
    if authorized?(socket, flow_id) do
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "flow:#{flow_id}")
      send(self(), :after_join)
      {:ok, assign(socket, :operator, operator_meta(params))}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("tenant:" <> tenant_id, _params, socket) do
    if socket.assigns.tenant_id == tenant_id do
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "tenant:#{tenant_id}")
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("instance:" <> instance_id, _params, socket) do
    if instance_authorized?(socket, instance_id) do
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "instance:#{instance_id}")
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    %{id: id, name: name} = socket.assigns.operator

    {:ok, _ref} =
      Presence.track(socket, id, %{
        name: name,
        online_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # Forward PubSub events to connected clients
  def handle_info(%{type: type, payload: payload} = msg, socket) do
    timestamp = Map.get(msg, :timestamp, DateTime.utc_now())

    push(socket, type, %{
      payload: payload,
      timestamp: DateTime.to_iso8601(timestamp)
    })

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp operator_meta(params) do
    %{
      id: params["operator_id"] || "op-" <> Ecto.UUID.generate(),
      name: params["operator_name"] || "Operator"
    }
  end

  defp authorized?(socket, flow_id) do
    case Kalcifer.Flows.get_flow(flow_id) do
      %{tenant_id: tid} -> tid == socket.assigns.tenant_id
      _ -> false
    end
  end

  # Confirm the instance belongs to the socket's tenant — otherwise any
  # tenant could subscribe to another's live engine events by instance id.
  defp instance_authorized?(socket, instance_id) do
    case Kalcifer.Engine.Persistence.InstanceStore.get_instance(instance_id) do
      %{tenant_id: tid} -> tid == socket.assigns.tenant_id
      _ -> false
    end
  end
end
