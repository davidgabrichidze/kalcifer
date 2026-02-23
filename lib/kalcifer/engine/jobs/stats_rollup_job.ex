defmodule Kalcifer.Engine.Jobs.StatsRollupJob do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Kalcifer.Analytics.Collector

  @impl true
  def perform(_job) do
    Collector.flush()
    :ok
  end
end
