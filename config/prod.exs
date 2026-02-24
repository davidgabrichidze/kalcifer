import Config

config :kalcifer, KalciferWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  exclude: [
    hosts: ["localhost", "127.0.0.1"]
  ]

# Do not print debug messages in production
config :logger, level: :info

# JSON structured logging for production
config :logger, :default_handler, formatter: {LoggerJSON.Formatters.Basic, metadata: :all}

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
