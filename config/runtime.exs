import Config

if System.get_env("PHX_SERVER") do
  config :kalcifer, KalciferWeb.Endpoint, server: true
end

config :kalcifer, KalciferWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :kalcifer, Kalcifer.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "20")),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"

  config :kalcifer, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :kalcifer, KalciferWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # Oban production config
  config :kalcifer, Oban,
    repo: Kalcifer.Repo,
    queues: [
      journey_triggers: 10,
      delayed_resume: 20,
      maintenance: 5
    ],
    plugins: [
      {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}
    ]
end
