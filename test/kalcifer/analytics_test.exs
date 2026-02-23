defmodule Kalcifer.AnalyticsTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Analytics

  describe "flow stats" do
    test "upsert_flow_stats creates new record" do
      flow = insert(:flow)
      today = Date.utc_today()

      assert {:ok, stats} =
               Analytics.upsert_flow_stats(flow.id, 1, today, %{entered: 5, completed: 3})

      assert stats.entered == 5
      assert stats.completed == 3
    end

    test "upsert_flow_stats increments existing record" do
      flow = insert(:flow)
      today = Date.utc_today()

      {:ok, _} = Analytics.upsert_flow_stats(flow.id, 1, today, %{entered: 5, completed: 3})
      {:ok, _} = Analytics.upsert_flow_stats(flow.id, 1, today, %{entered: 2, completed: 1})

      summary = Analytics.flow_summary(flow.id, Date.range(today, today))
      assert summary.entered == 7
      assert summary.completed == 4
    end

    test "flow_summary returns zeros for no data" do
      flow_id = Ecto.UUID.generate()
      today = Date.utc_today()

      summary = Analytics.flow_summary(flow_id, Date.range(today, today))
      assert summary.entered == 0
      assert summary.completed == 0
    end
  end

  describe "node stats" do
    test "upsert_node_stats creates new record" do
      flow = insert(:flow)
      today = Date.utc_today()

      assert {:ok, stats} =
               Analytics.upsert_node_stats(flow.id, 1, "node_1", today, %{
                 executed: 10,
                 completed: 8,
                 failed: 2
               })

      assert stats.executed == 10
      assert stats.completed == 8
    end

    test "node_breakdown returns per-node stats" do
      flow = insert(:flow)
      today = Date.utc_today()

      Analytics.upsert_node_stats(flow.id, 1, "entry_1", today, %{executed: 10, completed: 10})
      Analytics.upsert_node_stats(flow.id, 1, "action_1", today, %{executed: 8, completed: 7})

      breakdown = Analytics.node_breakdown(flow.id, 1, Date.range(today, today))
      assert length(breakdown) == 2

      entry_stats = Enum.find(breakdown, &(&1.node_id == "entry_1"))
      assert entry_stats.executed == 10
    end

    test "ab_test_results aggregates branch counts" do
      flow = insert(:flow)
      today = Date.utc_today()

      Analytics.upsert_node_stats(flow.id, 1, "split_1", today, %{
        executed: 10,
        branch_counts: %{"variant_a" => 6, "variant_b" => 4}
      })

      results = Analytics.ab_test_results(flow.id, "split_1", Date.range(today, today))
      assert results["variant_a"] == 6
      assert results["variant_b"] == 4
    end
  end

  describe "conversions" do
    test "record_conversion creates conversion record" do
      instance = insert(:flow_instance)

      assert {:ok, conversion} =
               Analytics.record_conversion(%{
                 flow_id: instance.flow_id,
                 instance_id: instance.id,
                 customer_id: "cust_123",
                 conversion_type: "purchase",
                 value: 49.99,
                 converted_at: DateTime.utc_now() |> DateTime.truncate(:second)
               })

      assert conversion.conversion_type == "purchase"
      assert conversion.value == 49.99
    end

    test "conversion_count returns count in date range" do
      instance = insert(:flow_instance)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Analytics.record_conversion(%{
        flow_id: instance.flow_id,
        instance_id: instance.id,
        customer_id: "cust_1",
        conversion_type: "purchase",
        converted_at: now
      })

      Analytics.record_conversion(%{
        flow_id: instance.flow_id,
        instance_id: instance.id,
        customer_id: "cust_2",
        conversion_type: "signup",
        converted_at: now
      })

      today = Date.utc_today()
      count = Analytics.conversion_count(instance.flow_id, Date.range(today, today))
      assert count == 2
    end
  end

  describe "funnel" do
    test "returns ordered counts for node path" do
      flow = insert(:flow)
      today = Date.utc_today()

      Analytics.upsert_node_stats(flow.id, 1, "entry_1", today, %{executed: 100})
      Analytics.upsert_node_stats(flow.id, 1, "action_1", today, %{executed: 80})
      Analytics.upsert_node_stats(flow.id, 1, "exit_1", today, %{executed: 60})

      steps = Analytics.funnel(flow.id, ["entry_1", "action_1", "exit_1"])
      assert length(steps) == 3
      assert Enum.at(steps, 0).count == 100
      assert Enum.at(steps, 1).count == 80
      assert Enum.at(steps, 2).count == 60
    end
  end
end
