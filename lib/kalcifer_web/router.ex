defmodule KalciferWeb.Router do
  use KalciferWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api/v1", KalciferWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end
end
