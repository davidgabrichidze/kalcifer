defmodule KalciferWeb.FlowController do
  use KalciferWeb, :controller

  alias Kalcifer.Flows

  action_fallback KalciferWeb.FallbackController

  # --- CRUD ---

  def index(conn, params) do
    tenant = conn.assigns.current_tenant
    opts = if params["status"], do: [status: params["status"]], else: []
    flows = Flows.list_flows(tenant.id, opts)
    json(conn, %{data: Enum.map(flows, &serialize_flow/1)})
  end

  def create(conn, params) do
    tenant = conn.assigns.current_tenant

    with {:ok, flow} <- Flows.create_flow(tenant.id, atomize_flow_params(params)) do
      conn
      |> put_status(:created)
      |> json(%{data: serialize_flow(flow)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, flow} <- fetch_tenant_flow(conn, id) do
      json(conn, %{data: serialize_flow(flow)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, flow} <- fetch_tenant_flow(conn, id),
         {:ok, updated} <- Flows.update_flow(flow, atomize_flow_params(params)) do
      json(conn, %{data: serialize_flow(updated)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, flow} <- fetch_tenant_flow(conn, id),
         {:ok, _flow} <- Flows.delete_flow(flow) do
      send_resp(conn, :no_content, "")
    end
  end

  # --- Lifecycle ---

  def activate(conn, %{"id" => id}) do
    with {:ok, flow} <- fetch_tenant_flow(conn, id),
         {:ok, flow} <- Flows.activate_flow(flow) do
      json(conn, %{data: serialize_flow(flow)})
    end
  end

  def pause(conn, %{"id" => id}) do
    with {:ok, flow} <- fetch_tenant_flow(conn, id),
         {:ok, flow} <- Flows.pause_flow(flow) do
      json(conn, %{data: serialize_flow(flow)})
    end
  end

  def archive(conn, %{"id" => id}) do
    with {:ok, flow} <- fetch_tenant_flow(conn, id),
         {:ok, flow} <- Flows.archive_flow(flow) do
      json(conn, %{data: serialize_flow(flow)})
    end
  end

  # --- Private ---

  defp fetch_tenant_flow(conn, id) do
    tenant = conn.assigns.current_tenant

    case Flows.get_flow(id) do
      %{tenant_id: tenant_id} = flow when tenant_id == tenant.id -> {:ok, flow}
      _ -> {:error, :not_found}
    end
  end

  defp serialize_flow(flow) do
    %{
      id: flow.id,
      name: flow.name,
      description: flow.description,
      status: flow.status,
      active_version_id: flow.active_version_id,
      entry_config: flow.entry_config,
      exit_criteria: flow.exit_criteria,
      frequency_cap: flow.frequency_cap,
      inserted_at: flow.inserted_at,
      updated_at: flow.updated_at
    }
  end

  defp atomize_flow_params(params) do
    params
    |> Map.take(["name", "description", "entry_config", "exit_criteria", "frequency_cap"])
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
