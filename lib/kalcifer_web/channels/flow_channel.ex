defmodule KalciferWeb.FlowChannel do
  @moduledoc false

  use Phoenix.Channel

  @impl true
  def join("flow:" <> flow_id, _params, socket) do
    if authorized?(socket, flow_id) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("tenant:" <> tenant_id, _params, socket) do
    if socket.assigns.tenant_id == tenant_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("instance:" <> _instance_id, _params, socket) do
    # Allow any authenticated tenant — fine-grained auth can be added later
    if socket.assigns[:tenant_id] do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  defp authorized?(socket, flow_id) do
    case Kalcifer.Flows.get_flow(flow_id) do
      %{tenant_id: tid} -> tid == socket.assigns.tenant_id
      _ -> false
    end
  end
end
