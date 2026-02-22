import Config

# Configure your database
config :kalcifer, Kalcifer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kalcifer_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :kalcifer, KalciferWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "3N0BaKyT8inIgF+Hvx8ttyWB0a9I4xMP8bj81Z8wxYBIO5auMucUceQSAaf2fgGG",
  watchers: []

# Enable dev routes for dashboard
config :kalcifer, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
