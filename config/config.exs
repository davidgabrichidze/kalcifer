import Config

config :kalcifer,
  ecto_repos: [Kalcifer.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :kalcifer, KalciferWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: KalciferWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Kalcifer.PubSub

# Oban job processing
config :kalcifer, Oban,
  repo: Kalcifer.Repo,
  queues: [
    flow_triggers: 10,
    delayed_resume: 20,
    channel_delivery: 50,
    maintenance: 5
  ],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", Kalcifer.Engine.Jobs.CleanupJob},
       {"*/5 * * * *", Kalcifer.Engine.Jobs.StatsRollupJob}
     ]}
  ]

# Rate limiting — {max_requests, window_seconds}
config :kalcifer, :rate_limits, %{
  trigger: {100, 60},
  events: {1000, 60},
  default: {500, 60}
}

# Channel providers — channel atom → provider module
config :kalcifer, :channel_providers, %{
  email: Kalcifer.Channels.Providers.LogProvider,
  sms: Kalcifer.Channels.Providers.LogProvider,
  push: Kalcifer.Channels.Providers.LogProvider,
  whatsapp: Kalcifer.Channels.Providers.LogProvider,
  in_app: Kalcifer.Channels.Providers.LogProvider,
  webhook: Kalcifer.Channels.Providers.LogProvider
}

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
