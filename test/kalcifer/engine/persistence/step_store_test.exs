defmodule Kalcifer.Engine.Persistence.StepStoreTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Engine.Persistence.StepStore

  import Kalcifer.Factory

  describe "record_step_start/3" do
    test "records a step start" do
      instance = insert(:flow_instance)

      node = %{
        "id" => "entry_1",
        "type" => "event_entry",
        "config" => %{"event_type" => "signup"}
      }

      assert {:ok, step} = StepStore.record_step_start(instance.id, node, 1)
      assert step.node_id == "entry_1"
      assert step.node_type == "event_entry"
      assert step.status == "started"
      assert step.started_at != nil
    end
  end

  describe "record_step_complete/2" do
    test "marks step as completed with output" do
      instance = insert(:flow_instance)
      node = %{"id" => "entry_1", "type" => "event_entry", "config" => %{}}
      {:ok, step} = StepStore.record_step_start(instance.id, node, 1)

      assert {:ok, completed} = StepStore.record_step_complete(step, %{event_type: "signup"})
      assert completed.status == "completed"
      assert completed.output == %{event_type: "signup"}
      assert completed.completed_at != nil
    end
  end

  describe "record_step_fail/2" do
    test "marks step as failed with error" do
      instance = insert(:flow_instance)
      node = %{"id" => "entry_1", "type" => "event_entry", "config" => %{}}
      {:ok, step} = StepStore.record_step_start(instance.id, node, 1)

      error = %{reason: "connection refused"}
      assert {:ok, failed} = StepStore.record_step_fail(step, error)
      assert failed.status == "failed"
      assert failed.error == %{reason: "connection refused"}
    end
  end

  describe "list_steps/1" do
    test "returns steps ordered by started_at" do
      instance = insert(:flow_instance)
      node_a = %{"id" => "a", "type" => "send_email", "config" => %{}}
      node_b = %{"id" => "b", "type" => "send_sms", "config" => %{}}

      {:ok, _} = StepStore.record_step_start(instance.id, node_a, 1)
      Process.sleep(10)
      {:ok, _} = StepStore.record_step_start(instance.id, node_b, 1)

      steps = StepStore.list_steps(instance.id)
      assert length(steps) == 2
      assert [%{node_id: "a"}, %{node_id: "b"}] = steps
    end

    test "returns empty list for instance with no steps" do
      instance = insert(:flow_instance)
      assert StepStore.list_steps(instance.id) == []
    end
  end

  describe "count_channel_steps_for_customer/3" do
    test "counts completed channel steps within time window" do
      flow = insert(:flow)
      instance = insert(:flow_instance, flow: flow, tenant: flow.tenant, customer_id: "cust_1")

      node = %{"id" => "email_1", "type" => "send_email", "config" => %{}}
      {:ok, step} = StepStore.record_step_start(instance.id, node, 1)
      {:ok, _} = StepStore.record_step_complete(step, %{sent: true})

      since = DateTime.utc_now() |> DateTime.add(-3600)
      count = StepStore.count_channel_steps_for_customer("cust_1", ["send_email"], since)
      assert count == 1
    end

    test "excludes steps outside time window" do
      since = DateTime.utc_now() |> DateTime.add(3600)
      count = StepStore.count_channel_steps_for_customer("nobody", ["send_email"], since)
      assert count == 0
    end
  end
end
