defmodule Kalcifer.Analytics.CollectorTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Ecto.Adapters.SQL.Sandbox
  alias Kalcifer.Analytics
  alias Kalcifer.Analytics.Collector
  alias Kalcifer.Repo

  setup do
    {:ok, pid} = Collector.start_link(name: :"collector_#{System.unique_integer()}")
    Sandbox.allow(Repo, self(), pid)
    %{collector: pid}
  end

  test "batches step events and flushes to DB", %{collector: pid} do
    flow = insert(:flow)

    Collector.record_step(pid, %{
      flow_id: flow.id,
      version_number: 1,
      node_id: "entry_1",
      status: :completed,
      branch_key: nil
    })

    Collector.record_step(pid, %{
      flow_id: flow.id,
      version_number: 1,
      node_id: "entry_1",
      status: :completed,
      branch_key: nil
    })

    Collector.flush(pid)

    today = Date.utc_today()
    breakdown = Analytics.node_breakdown(flow.id, 1, Date.range(today, today))
    assert length(breakdown) == 1
    assert hd(breakdown).executed == 2
    assert hd(breakdown).completed == 2
  end

  test "batches instance events and flushes to DB", %{collector: pid} do
    flow = insert(:flow)

    Collector.record_instance(pid, %{
      flow_id: flow.id,
      version_number: 1,
      type: :entered
    })

    Collector.record_instance(pid, %{
      flow_id: flow.id,
      version_number: 1,
      type: :completed
    })

    Collector.flush(pid)

    today = Date.utc_today()
    summary = Analytics.flow_summary(flow.id, Date.range(today, today))
    assert summary.entered == 1
    assert summary.completed == 1
  end

  test "tracks branch counts for branched nodes", %{collector: pid} do
    flow = insert(:flow)

    Collector.record_step(pid, %{
      flow_id: flow.id,
      version_number: 1,
      node_id: "split_1",
      status: :completed,
      branch_key: "variant_a"
    })

    Collector.record_step(pid, %{
      flow_id: flow.id,
      version_number: 1,
      node_id: "split_1",
      status: :completed,
      branch_key: "variant_b"
    })

    Collector.flush(pid)

    today = Date.utc_today()
    results = Analytics.ab_test_results(flow.id, "split_1", Date.range(today, today))
    assert results["variant_a"] == 1
    assert results["variant_b"] == 1
  end

  test "tracks failed steps", %{collector: pid} do
    flow = insert(:flow)

    Collector.record_step(pid, %{
      flow_id: flow.id,
      version_number: 1,
      node_id: "action_1",
      status: :failed,
      branch_key: nil
    })

    Collector.flush(pid)

    today = Date.utc_today()
    breakdown = Analytics.node_breakdown(flow.id, 1, Date.range(today, today))
    assert hd(breakdown).failed == 1
  end
end
