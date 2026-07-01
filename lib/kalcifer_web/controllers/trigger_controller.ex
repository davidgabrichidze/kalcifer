defmodule KalciferWeb.TriggerController do
  use KalciferWeb, :controller

  alias Kalcifer.Engine.FlowTrigger
  alias Kalcifer.Flows
  alias KalciferWeb.Params

  action_fallback KalciferWeb.FallbackController

  @create_schema [
    customer_id: [type: {:custom, Params, :non_empty_string, []}, required: true],
    dry_run: [type: :boolean, default: false],
    context: [type: {:custom, Params, :json_map, []}, default: %{}]
  ]

  def create(conn, %{"flow_id" => flow_id} = params) do
    tenant = conn.assigns.current_tenant

    with {:ok, p} <- Params.validate(params, @create_schema),
         {:ok, _flow} <- fetch_tenant_flow(tenant, flow_id),
         {:ok, instance_id} <-
           FlowTrigger.trigger(flow_id, p.customer_id, p.context, dry_run: p.dry_run) do
      conn
      |> put_status(:created)
      |> json(%{instance_id: instance_id})
    end
  end

  defp fetch_tenant_flow(tenant, flow_id) do
    case Flows.get_flow(flow_id) do
      %{tenant_id: tenant_id} = flow when tenant_id == tenant.id -> {:ok, flow}
      _ -> {:error, :not_found}
    end
  end
end
