defmodule Kalcifer.Analytics.RollupTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Analytics
  alias Kalcifer.Engine.Jobs.StatsRollupJob

  setup do
    tenant = insert(:tenant)
    flow = insert(:flow, tenant: tenant)
    {:ok, tenant: tenant, flow: flow}
  end

  defp insert_instance(ctx, attrs) do
    defaults = [tenant: ctx.tenant, flow: ctx.flow, version_number: 1, dry_run: false]
    insert(:flow_instance, Keyword.merge(defaults, attrs))
  end

  test "recompute_date rebuilds flow stats from instances", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    today = Date.utc_today()

    insert_instance(ctx, status: "running", entered_at: now)
    insert_instance(ctx, status: "completed", entered_at: now, completed_at: now)
    insert_instance(ctx, status: "failed", entered_at: now)
    insert_instance(ctx, status: "completed", entered_at: now, dry_run: true)

    assert :ok = Analytics.recompute_date(today)

    summary = Analytics.flow_summary(ctx.flow.id, Date.range(today, today))
    assert summary.entered == 3
    assert summary.completed == 1
    assert summary.failed == 1
  end

  test "recompute_date rebuilds node stats from execution steps", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    today = Date.utc_today()
    instance = insert_instance(ctx, status: "completed", entered_at: now)

    insert(:execution_step,
      instance: instance,
      node_id: "n1",
      status: "completed",
      started_at: now
    )

    insert(:execution_step,
      instance: instance,
      node_id: "n1",
      status: "failed",
      started_at: now
    )

    assert :ok = Analytics.recompute_date(today)

    assert [%{node_id: "n1", executed: 2, completed: 1, failed: 1}] =
             Analytics.node_breakdown(ctx.flow.id, 1, Date.range(today, today))
  end

  test "recompute_date overwrites drifted counters", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    today = Date.utc_today()

    insert_instance(ctx, status: "completed", entered_at: now, completed_at: now)

    # Simulate collector drift (double-counted entries)
    Analytics.upsert_flow_stats(ctx.flow.id, 1, today, %{entered: 10, completed: 10})

    assert :ok = Analytics.recompute_date(today)

    summary = Analytics.flow_summary(ctx.flow.id, Date.range(today, today))
    assert summary.entered == 1
    assert summary.completed == 1
  end

  test "StatsRollupJob rolls up the date given in args", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    today = Date.utc_today()

    insert_instance(ctx, status: "completed", entered_at: now, completed_at: now)

    assert :ok = StatsRollupJob.perform(%Oban.Job{args: %{"date" => Date.to_iso8601(today)}})

    summary = Analytics.flow_summary(ctx.flow.id, Date.range(today, today))
    assert summary.entered == 1
  end
end
