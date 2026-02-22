defmodule KalciferWeb.HealthController do
  use KalciferWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end
end
