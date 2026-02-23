defmodule KalciferWeb.Router do
  use KalciferWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug KalciferWeb.Plugs.ApiKeyAuth
  end

  scope "/api/v1", KalciferWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/health/metrics", HealthController, :metrics

    post "/webhooks/sendgrid", WebhookController, :sendgrid
    post "/webhooks/twilio", WebhookController, :twilio
  end

  scope "/api/v1", KalciferWeb do
    pipe_through [:api, :authenticated]

    resources "/flows", FlowController, except: [:new, :edit] do
      resources "/versions", FlowVersionController,
        only: [:index, :create, :show],
        param: "version_number"
    end

    post "/flows/:id/activate", FlowController, :activate
    post "/flows/:id/pause", FlowController, :pause
    post "/flows/:id/archive", FlowController, :archive

    post "/flows/:flow_id/versions/:version_number/migrate", MigrationController, :migrate
    post "/flows/:flow_id/versions/:version_number/rollback", MigrationController, :rollback
    get "/flows/:flow_id/migration_status", MigrationController, :status

    post "/flows/:flow_id/trigger", TriggerController, :create
    post "/events", EventController, :create

    resources "/journeys", JourneyController, except: [:new, :edit]

    post "/journeys/:id/launch", JourneyController, :launch
    post "/journeys/:id/pause", JourneyController, :pause
    post "/journeys/:id/archive", JourneyController, :archive
  end
end
