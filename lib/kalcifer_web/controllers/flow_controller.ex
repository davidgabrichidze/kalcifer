defmodule KalciferWeb.FlowController do
  use KalciferWeb, :controller

  alias Kalcifer.Customers
  alias Kalcifer.Engine.NodeRegistry
  alias Kalcifer.Flows
  alias Kalcifer.Flows.FlowGraph

  action_fallback KalciferWeb.FallbackController

  # --- CRUD ---

  def index(conn, params) do
    tenant = resolve_tenant(conn)
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
         {:ok, result} <- Flows.activate_flow(flow) do
      case result do
        {flow, %{warnings: warnings, context_deps: context_deps}} ->
          json(conn, %{
            data: serialize_flow(flow),
            preflight: %{warnings: warnings, context_deps: context_deps}
          })

        flow ->
          json(conn, %{data: serialize_flow(flow)})
      end
    end
  end

  def preflight(conn, %{"id" => id}) do
    tenant = resolve_tenant(conn)

    with {:ok, flow} <- fetch_tenant_flow(conn, id),
         version when not is_nil(version) <- get_latest_version(flow),
         {:ok, result} <- FlowGraph.preflight(version.graph, NodeRegistry) do
      field_coverage =
        case result.context_deps do
          [] -> %{}
          deps -> Customers.field_coverage(tenant.id, deps)
        end

      json(conn, %{
        data: %{
          warnings: result.warnings,
          context_deps: result.context_deps,
          field_coverage: field_coverage
        }
      })
    else
      nil -> {:error, :no_draft_version}
      error -> error
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
    tenant = resolve_tenant(conn)

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

  defp get_latest_version(flow) do
    flow.id
    |> Flows.list_versions()
    |> List.last()
  end

  defp atomize_flow_params(params) do
    params
    |> Map.take(["name", "description", "entry_config", "exit_criteria", "frequency_cap"])
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  defp resolve_tenant(conn), do: KalciferWeb.TenantResolver.resolve(conn)
end
