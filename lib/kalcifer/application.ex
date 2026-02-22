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
      KalciferWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Kalcifer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    KalciferWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
