defmodule KalciferWeb.Plugs.RateLimiter.Sweeper do
  @moduledoc """
  Owns the rate-limiter ETS table and periodically drops buckets whose
  newest timestamp is older than the longest configured window, so the
  table can't grow unbounded with one entry per (tenant, action) ever
  seen. Also creates the table at boot so it survives request processes.
  """

  use GenServer

  @table :kalcifer_rate_limits
  @sweep_interval :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    ensure_table()
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep()
    {:noreply, state}
  end

  @doc "Drops buckets with no activity within the retention window."
  def sweep(now \\ System.system_time(:second)) do
    cutoff = now - retention_seconds()

    # {key, timestamps} — delete keys whose newest timestamp is stale.
    :ets.foldl(&drop_stale_bucket(&1, &2, cutoff), :ok, @table)
  end

  defp drop_stale_bucket({key, timestamps}, acc, cutoff) do
    if Enum.max(timestamps, fn -> 0 end) <= cutoff do
      :ets.delete(@table, key)
    end

    acc
  end

  defp retention_seconds do
    Application.get_env(:kalcifer, :rate_limits, %{})
    |> Map.values()
    |> Enum.map(fn {_max, window} -> window end)
    |> Enum.max(fn -> 60 end)
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:set, :public, :named_table])
      _ref -> @table
    end
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end
end
