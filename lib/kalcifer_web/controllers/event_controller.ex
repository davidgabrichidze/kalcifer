defmodule KalciferWeb.EventController do
  use KalciferWeb, :controller

  alias Kalcifer.Engine.EventRouter

  def create(conn, params) do
    customer_id = params["customer_id"]
    event_type = params["event_type"]
    event_data = params["data"] || %{}

    results = EventRouter.route_event(customer_id, event_type, event_data)

    conn
    |> put_status(:accepted)
    |> json(%{routed: length(results)})
  end
end
