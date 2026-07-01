defmodule KalciferWeb.Router do
  use KalciferWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug KalciferWeb.Plugs.ApiKeyAuth
    plug KalciferWeb.Plugs.RateLimiter, action: :default
  end

  scope "/api/v1", KalciferWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/health/metrics", HealthController, :metrics

    post "/webhooks/sendgrid", WebhookController, :sendgrid
    post "/webhooks/twilio", WebhookController, :twilio

    post "/chat", ChatController, :create

    # Auth
    post "/auth/google", AuthController, :google
    get "/auth/me", AuthController, :me

    get "/settings", SettingsController, :show
    put "/settings", SettingsController, :update
    get "/settings/stats", SettingsController, :stats
    post "/settings/regenerate-api-key", SettingsController, :regenerate_api_key

    get "/audit", AuditController, :index

    get "/deliveries", DeliveryController, :index
    get "/deliveries/stats", DeliveryController, :stats
    post "/deliveries/:id/status", DeliveryController, :update_status

    get "/engine", EngineController, :show

    # Browse mode — read-only flow/journey/version listing (dev frontend)
    get "/flows", FlowController, :index
    get "/flows/:id", FlowController, :show
    get "/flows/:flow_id/versions", FlowVersionController, :index
    get "/flows/:flow_id/versions/:version_number", FlowVersionController, :show
    get "/journeys", JourneyController, :index

    get "/flows/:id/export", FlowController, :export
    post "/flows/import", FlowController, :import_flow
    post "/flows/:flow_id/simulate", SimulationController, :create
    post "/flows/:id/preflight", FlowController, :preflight

    # Instance browsing (dev frontend, uses resolve_tenant fallback)
    get "/flows/:flow_id/instances", InstanceBrowseController, :index
    get "/instances/:id", InstanceBrowseController, :show
    get "/instances/:id/timeline", InstanceBrowseController, :timeline

    # Analytics (dev frontend, unauthenticated)
    get "/flows/:flow_id/analytics/summary", AnalyticsController, :summary
    get "/flows/:flow_id/analytics/nodes", AnalyticsController, :nodes
    get "/flows/:flow_id/analytics/funnel", AnalyticsController, :funnel

    get "/conversations", ConversationController, :index
    get "/conversations/:id", ConversationController, :show
    put "/conversations/:id", ConversationController, :update
    post "/conversations/:id/archive", ConversationController, :archive
    delete "/conversations/:id", ConversationController, :delete
  end

  scope "/api/v1", KalciferWeb do
    pipe_through [:api, :authenticated]

    resources "/flows", FlowController, only: [:create, :update, :delete] do
      resources "/versions", FlowVersionController,
        only: [:create],
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

    resources "/customers", CustomerController, except: [:new, :edit]
    post "/customers/:customer_id/tags", CustomerController, :add_tags
    delete "/customers/:customer_id/tags", CustomerController, :remove_tags
    put "/customers/:customer_id/preferences", CustomerController, :update_preferences

    resources "/segments", SegmentController, except: [:new, :edit]
    get "/segments/:segment_id/members", SegmentController, :members

    post "/instances/:id/cancel", InstanceController, :cancel

    get "/flows/:flow_id/nodes/:node_id/ab_results", AnalyticsController, :ab_results

    resources "/journeys", JourneyController, only: [:create, :show, :update, :delete]

    post "/journeys/:id/launch", JourneyController, :launch
    post "/journeys/:id/pause", JourneyController, :pause
    post "/journeys/:id/archive", JourneyController, :archive
  end
end
