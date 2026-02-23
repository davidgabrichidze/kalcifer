defmodule KalciferWeb.EventController do
  use KalciferWeb, :controller

  alias Kalcifer.Engine.EventRouter

  action_fallback KalciferWeb.FallbackController

  def create(conn, %{"customer_id" => cid, "event_type" => et} = params)
      when is_binary(cid) and cid != "" and is_binary(et) and et != "" do
    tenant = conn.assigns.current_tenant
    event_data = params["data"] || %{}

    results = EventRouter.route_event(tenant.id, cid, et, event_data)
    routed = Enum.count(results, &match?({:ok, _}, &1))

    conn
    |> put_status(:accepted)
    |> json(%{routed: routed})
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "customer_id and event_type are required"})
  end
end
