defmodule Kalcifer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KalciferWeb.Telemetry,
      Kalcifer.Repo,
      {DNSCluster, query: Application.get_env(:kalcifer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Kalcifer.PubSub},
      {Finch, name: Kalcifer.Finch},
      {Oban, Application.fetch_env!(:kalcifer, Oban)},
      Kalcifer.Engine.Supervisor,
      Kalcifer.Simulators.Engine,
      KalciferWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Kalcifer.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Attach logger handler to capture logs for Engine Room dashboard
    :logger.add_handler(
      :kalcifer_engine_log,
      Kalcifer.Engine.LogHandler,
      %{level: :info}
    )

    # Forward engine telemetry into batched analytics stats
    Kalcifer.Analytics.TelemetryForwarder.attach()

    result
  end

  @impl true
  def config_change(changed, _new, removed) do
    KalciferWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
