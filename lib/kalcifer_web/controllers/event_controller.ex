defmodule KalciferWeb.EventController do
  use KalciferWeb, :controller

  alias Kalcifer.Engine.EventRouter
  alias KalciferWeb.Params

  action_fallback KalciferWeb.FallbackController

  @create_schema [
    customer_id: [type: {:custom, Params, :non_empty_string, []}, required: true],
    event_type: [type: {:custom, Params, :non_empty_string, []}, required: true],
    data: [type: {:custom, Params, :json_map, []}, default: %{}]
  ]

  def create(conn, params) do
    tenant = conn.assigns.current_tenant

    with {:ok, p} <- Params.validate(params, @create_schema) do
      results = EventRouter.route_event(tenant.id, p.customer_id, p.event_type, p.data)
      routed = Enum.count(results, &match?({:ok, _}, &1))

      conn
      |> put_status(:accepted)
      |> json(%{routed: routed})
    end
  end
end
