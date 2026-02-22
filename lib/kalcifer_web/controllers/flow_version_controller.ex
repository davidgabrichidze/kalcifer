defmodule KalciferWeb.FlowVersionController do
  use KalciferWeb, :controller

  alias Kalcifer.Flows

  action_fallback KalciferWeb.FallbackController

  def index(conn, %{"flow_id" => flow_id}) do
    with {:ok, _flow} <- fetch_tenant_flow(conn, flow_id) do
      versions = Flows.list_versions(flow_id)
      json(conn, %{data: Enum.map(versions, &serialize_version/1)})
    end
  end

  def create(conn, %{"flow_id" => flow_id} = params) do
    with {:ok, flow} <- fetch_tenant_flow(conn, flow_id),
         {:ok, version} <- Flows.create_version(flow, version_params(params)) do
      conn
      |> put_status(:created)
      |> json(%{data: serialize_version(version)})
    end
  end

  def show(conn, %{"flow_id" => flow_id, "version_number" => version_number}) do
    with {:ok, _flow} <- fetch_tenant_flow(conn, flow_id),
         {vn, ""} <- Integer.parse(version_number),
         %{} = version <- Flows.get_version(flow_id, vn) do
      json(conn, %{data: serialize_version(version)})
    else
      nil -> {:error, :not_found}
      :error -> {:error, :not_found}
      error -> error
    end
  end

  defp fetch_tenant_flow(conn, flow_id) do
    tenant = conn.assigns.current_tenant

    case Flows.get_flow(flow_id) do
      %{tenant_id: tenant_id} = flow when tenant_id == tenant.id -> {:ok, flow}
      _ -> {:error, :not_found}
    end
  end

  defp version_params(params) do
    %{
      graph: params["graph"],
      changelog: params["changelog"]
    }
  end

  defp serialize_version(version) do
    %{
      id: version.id,
      version_number: version.version_number,
      graph: version.graph,
      status: version.status,
      changelog: version.changelog,
      published_at: version.published_at,
      inserted_at: version.inserted_at,
      updated_at: version.updated_at
    }
  end
end
