defmodule Kalcifer.Engine.Jobs.StatsRollupJob do
  @moduledoc """
  Daily analytics rollup. Flushes the in-memory Collector, then
  recomputes the target date's stats from the database source of truth
  (flow_instances + execution_steps), correcting any drift from
  collector restarts. Runs for yesterday unless args provide a "date".
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Kalcifer.Analytics
  alias Kalcifer.Analytics.Collector

  @impl true
  def perform(%Oban.Job{args: args}) do
    Collector.flush()

    args
    |> target_date()
    |> Analytics.recompute_date()
  end

  defp target_date(%{"date" => date}) when is_binary(date), do: Date.from_iso8601!(date)
  defp target_date(_args), do: Date.add(Date.utc_today(), -1)
end
