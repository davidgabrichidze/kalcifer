defmodule Kalcifer.Engine.Persistence.StepStoreTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Engine.Persistence.StepStore

  import Kalcifer.Factory

  describe "record_step_start/3" do
    test "records a step start" do
      instance = insert(:journey_instance)

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
      instance = insert(:journey_instance)
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
      instance = insert(:journey_instance)
      node = %{"id" => "entry_1", "type" => "event_entry", "config" => %{}}
      {:ok, step} = StepStore.record_step_start(instance.id, node, 1)

      error = %{reason: "connection refused"}
      assert {:ok, failed} = StepStore.record_step_fail(step, error)
      assert failed.status == "failed"
      assert failed.error == %{reason: "connection refused"}
    end
  end
end
