defmodule KalciferWeb.Plugs.RateLimiter.SweeperTest do
  use ExUnit.Case, async: false

  alias KalciferWeb.Plugs.RateLimiter.Sweeper

  @table :kalcifer_rate_limits

  setup do
    # The table is created at boot by the supervised Sweeper.
    :ets.delete_all_objects(@table)
    on_exit(fn -> :ets.delete_all_objects(@table) end)
    :ok
  end

  test "drops buckets with only stale timestamps" do
    now = System.system_time(:second)

    # default window is 60s; retention is the max configured window.
    :ets.insert(@table, {"stale:default", [now - 100_000]})
    :ets.insert(@table, {"fresh:default", [now]})

    Sweeper.sweep(now)

    assert :ets.lookup(@table, "stale:default") == []
    assert [{"fresh:default", _}] = :ets.lookup(@table, "fresh:default")
  end

  test "keeps a bucket if any timestamp is within the window" do
    now = System.system_time(:second)
    :ets.insert(@table, {"mixed:default", [now - 100_000, now - 1]})

    Sweeper.sweep(now)

    assert [{"mixed:default", _}] = :ets.lookup(@table, "mixed:default")
  end
end
