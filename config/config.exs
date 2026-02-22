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
    journey_triggers: 10,
    delayed_resume: 20,
    maintenance: 5
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
