defmodule Kalcifer.MixProject do
  use Mix.Project

  def project do
    [
      app: :kalcifer,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {Kalcifer.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Web
      {:phoenix, "~> 1.7"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.5"},
      {:corsica, "~> 2.1"},

      # Database
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},

      # Job processing
      {:oban, "~> 2.18"},

      # Data pipeline
      {:broadway, "~> 1.1"},

      # HTTP client
      {:finch, "~> 0.19"},
      {:req, "~> 0.5"},

      # Auth
      {:guardian, "~> 2.3"},
      {:argon2_elixir, "~> 4.0"},

      # Encryption
      {:cloak_ecto, "~> 1.3"},

      # Serialization
      {:jason, "~> 1.4"},

      # Observability
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:logger_json, "~> 7.0"},

      # Clustering
      {:dns_cluster, "~> 0.2.0"},
      {:libcluster, "~> 3.3"},

      # Utilities
      {:nimble_options, "~> 1.1"},

      # i18n
      {:gettext, "~> 1.0"},

      # Dev & Test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_machina, "~> 2.8", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:benchee, "~> 1.3", only: :dev}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
