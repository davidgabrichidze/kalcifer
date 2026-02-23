defmodule KalciferWeb.TriggerController do
  use KalciferWeb, :controller

  alias Kalcifer.Engine.FlowTrigger
  alias Kalcifer.Flows

  action_fallback KalciferWeb.FallbackController

  def create(conn, %{"flow_id" => flow_id, "customer_id" => cid} = params)
      when is_binary(cid) and cid != "" do
    tenant = conn.assigns.current_tenant

    with {:ok, _flow} <- fetch_tenant_flow(tenant, flow_id),
         {:ok, instance_id} <-
           FlowTrigger.trigger(flow_id, cid, params["context"] || %{}) do
      conn
      |> put_status(:created)
      |> json(%{instance_id: instance_id})
    end
  end

  def create(conn, %{"flow_id" => _flow_id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "customer_id is required"})
  end

  defp fetch_tenant_flow(tenant, flow_id) do
    case Flows.get_flow(flow_id) do
      %{tenant_id: tenant_id} = flow when tenant_id == tenant.id -> {:ok, flow}
      _ -> {:error, :not_found}
    end
  end
end
