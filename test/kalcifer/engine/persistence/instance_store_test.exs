defmodule Kalcifer.Engine.Persistence.InstanceStoreTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Engine.Persistence.InstanceStore

  import Kalcifer.Factory

  describe "create_instance/1" do
    test "creates a journey instance" do
      journey = insert(:journey)
      tenant = journey.tenant

      assert {:ok, instance} =
               InstanceStore.create_instance(%{
                 journey_id: journey.id,
                 version_number: 1,
                 customer_id: "customer_1",
                 tenant_id: tenant.id,
                 current_nodes: ["entry_1"]
               })

      assert instance.status == "running"
      assert instance.current_nodes == ["entry_1"]
      assert instance.entered_at != nil
    end
  end

  describe "get_instance/1" do
    test "returns instance by id" do
      instance = insert(:journey_instance)
      found = InstanceStore.get_instance(instance.id)
      assert found.id == instance.id
    end

    test "returns nil for non-existent id" do
      assert InstanceStore.get_instance(Ecto.UUID.generate()) == nil
    end
  end

  describe "update_current_nodes/2" do
    test "updates the current nodes list" do
      instance = insert(:journey_instance, current_nodes: ["entry_1"])
      assert {:ok, updated} = InstanceStore.update_current_nodes(instance, ["node_2", "node_3"])
      assert updated.current_nodes == ["node_2", "node_3"]
    end
  end

  describe "complete_instance/1" do
    test "marks instance as completed" do
      instance = insert(:journey_instance)
      assert {:ok, completed} = InstanceStore.complete_instance(instance)
      assert completed.status == "completed"
      assert completed.completed_at != nil
      assert completed.current_nodes == []
    end
  end

  describe "fail_instance/2" do
    test "marks instance as failed with reason" do
      instance = insert(:journey_instance)
      assert {:ok, failed} = InstanceStore.fail_instance(instance, "node crashed")
      assert failed.status == "failed"
      assert failed.exit_reason == "node crashed"
      assert failed.exited_at != nil
    end
  end
end
