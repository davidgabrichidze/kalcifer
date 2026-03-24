defmodule KalciferWeb.FlowChannel do
  @moduledoc """
  Phoenix Channel for real-time flow/instance/tenant events.

  Subscribes to PubSub on join and pushes engine events to clients.
  Topics: flow:{id}, tenant:{id}, instance:{id}
  """

  use Phoenix.Channel

  @impl true
  def join("flow:" <> flow_id, _params, socket) do
    if authorized?(socket, flow_id) do
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "flow:#{flow_id}")
      {:ok, socket}
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
    if socket.assigns[:tenant_id] do
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "instance:#{instance_id}")
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Forward PubSub events to connected clients
  @impl true
  def handle_info(%{type: type, payload: payload} = msg, socket) do
    timestamp = Map.get(msg, :timestamp, DateTime.utc_now())

    push(socket, type, %{
      payload: payload,
      timestamp: DateTime.to_iso8601(timestamp)
    })

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp authorized?(socket, flow_id) do
    case Kalcifer.Flows.get_flow(flow_id) do
      %{tenant_id: tid} -> tid == socket.assigns.tenant_id
      _ -> false
    end
  end
end
