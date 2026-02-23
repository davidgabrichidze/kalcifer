defmodule KalciferWeb.JourneyController do
  use KalciferWeb, :controller

  alias Kalcifer.Marketing

  action_fallback KalciferWeb.FallbackController

  # --- CRUD ---

  def index(conn, params) do
    tenant = conn.assigns.current_tenant
    opts = if params["status"], do: [status: params["status"]], else: []
    journeys = Marketing.list_journeys(tenant.id, opts)
    json(conn, %{data: Enum.map(journeys, &serialize_journey/1)})
  end

  def create(conn, params) do
    tenant = conn.assigns.current_tenant

    with {:ok, journey} <- Marketing.create_journey(tenant.id, atomize_journey_params(params)) do
      conn
      |> put_status(:created)
      |> json(%{data: serialize_journey(journey)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, journey} <- fetch_tenant_journey(conn, id) do
      json(conn, %{data: serialize_journey(journey)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, journey} <- fetch_tenant_journey(conn, id),
         {:ok, updated} <- Marketing.update_journey(journey, atomize_journey_params(params)) do
      json(conn, %{data: serialize_journey(updated)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, journey} <- fetch_tenant_journey(conn, id),
         {:ok, _journey} <- Marketing.delete_journey(journey) do
      send_resp(conn, :no_content, "")
    end
  end

  # --- Lifecycle ---

  def launch(conn, %{"id" => id}) do
    with {:ok, journey} <- fetch_tenant_journey(conn, id),
         {:ok, launched} <- Marketing.launch_journey(journey) do
      json(conn, %{data: serialize_journey(launched)})
    end
  end

  def pause(conn, %{"id" => id}) do
    with {:ok, journey} <- fetch_tenant_journey(conn, id),
         {:ok, paused} <- Marketing.pause_journey(journey) do
      json(conn, %{data: serialize_journey(paused)})
    end
  end

  def archive(conn, %{"id" => id}) do
    with {:ok, journey} <- fetch_tenant_journey(conn, id),
         {:ok, archived} <- Marketing.archive_journey(journey) do
      json(conn, %{data: serialize_journey(archived)})
    end
  end

  # --- Private ---

  defp fetch_tenant_journey(conn, id) do
    tenant = conn.assigns.current_tenant

    case Marketing.get_journey(id) do
      %{tenant_id: tenant_id} = journey when tenant_id == tenant.id -> {:ok, journey}
      _ -> {:error, :not_found}
    end
  end

  defp serialize_journey(journey) do
    %{
      id: journey.id,
      name: journey.name,
      description: journey.description,
      status: journey.status,
      flow_id: journey.flow_id,
      goal_config: journey.goal_config,
      schedule: journey.schedule,
      audience_criteria: journey.audience_criteria,
      tags: journey.tags,
      inserted_at: journey.inserted_at,
      updated_at: journey.updated_at
    }
  end

  defp atomize_journey_params(params) do
    params
    |> Map.take([
      "name",
      "description",
      "flow_id",
      "goal_config",
      "schedule",
      "audience_criteria",
      "tags"
    ])
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
