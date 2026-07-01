defmodule Kalcifer.Analytics.TelemetryForwarderTest do
  # async: false — redirects the app-env collector target
  use Kalcifer.DataCase, async: false

  import Kalcifer.Factory

  alias Ecto.Adapters.SQL.Sandbox
  alias Kalcifer.Analytics
  alias Kalcifer.Analytics.Collector
  alias Kalcifer.Repo

  setup do
    name = :"collector_fwd_#{System.unique_integer([:positive])}"
    {:ok, pid} = Collector.start_link(name: name)
    Sandbox.allow(Repo, self(), pid)

    Application.put_env(:kalcifer, :analytics_collector, name)
    on_exit(fn -> Application.put_env(:kalcifer, :analytics_collector, :disabled) end)

    %{collector: name}
  end

  defp emit_step(flow, attrs \\ %{}) do
    :telemetry.execute(
      [:kalcifer, :step, :complete],
      %{system_time: System.system_time()},
      Map.merge(
        %{
          flow_id: flow.id,
          version_number: 1,
          instance_id: Ecto.UUID.generate(),
          node_id: "n1",
          node_type: "wait",
          status: :completed,
          branch_key: nil,
          dry_run: false
        },
        attrs
      )
    )
  end

  defp emit_instance(flow, type, attrs \\ %{}) do
    :telemetry.execute(
      [:kalcifer, :instance, type],
      %{system_time: System.system_time()},
      Map.merge(
        %{
          flow_id: flow.id,
          version_number: 1,
          instance_id: Ecto.UUID.generate(),
          customer_id: "cust-1",
          tenant_id: Ecto.UUID.generate(),
          dry_run: false
        },
        attrs
      )
    )
  end

  test "step telemetry is forwarded and lands in node stats", %{collector: name} do
    flow = insert(:flow)

    emit_step(flow)
    emit_step(flow, %{status: :failed})

    Collector.flush(name)

    today = Date.utc_today()

    assert [%{node_id: "n1", executed: 2, completed: 1, failed: 1}] =
             Analytics.node_breakdown(flow.id, 1, Date.range(today, today))
  end

  test "instance telemetry is forwarded and lands in flow stats", %{collector: name} do
    flow = insert(:flow)

    emit_instance(flow, :entered)
    emit_instance(flow, :completed)
    emit_instance(flow, :failed)

    Collector.flush(name)

    today = Date.utc_today()
    summary = Analytics.flow_summary(flow.id, Date.range(today, today))

    assert summary.entered == 1
    assert summary.completed == 1
    assert summary.failed == 1
  end

  test "dry-run events are ignored", %{collector: name} do
    flow = insert(:flow)

    emit_step(flow, %{dry_run: true})
    emit_instance(flow, :entered, %{dry_run: true})

    Collector.flush(name)

    today = Date.utc_today()

    assert Analytics.node_breakdown(flow.id, 1, Date.range(today, today)) == []
    assert Analytics.flow_summary(flow.id, Date.range(today, today)).entered == 0
  end
end
