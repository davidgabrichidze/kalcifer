import Config

# Configure your database
config :kalcifer, Kalcifer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kalcifer_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :kalcifer, KalciferWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4502],
  secret_key_base: "sLhN+b1jztN1IAzg+jYE5V0tz5+kEPdyCqhqjBOXVnDOlHIEUmsQ6Z40X03GdGiG",
  server: false

# Oban testing mode
config :kalcifer, Oban, testing: :inline

# Print only warnings and errors during test
config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
