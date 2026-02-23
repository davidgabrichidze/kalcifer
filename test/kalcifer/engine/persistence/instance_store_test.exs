defmodule Kalcifer.Engine.Persistence.InstanceStoreTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Engine.Persistence.InstanceStore

  import Kalcifer.Factory

  describe "create_instance/1" do
    test "creates a flow instance" do
      flow = insert(:flow)
      tenant = flow.tenant

      assert {:ok, instance} =
               InstanceStore.create_instance(%{
                 flow_id: flow.id,
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
      instance = insert(:flow_instance)
      found = InstanceStore.get_instance(instance.id)
      assert found.id == instance.id
    end

    test "returns nil for non-existent id" do
      assert InstanceStore.get_instance(Ecto.UUID.generate()) == nil
    end
  end

  describe "update_current_nodes/2" do
    test "updates the current nodes list" do
      instance = insert(:flow_instance, current_nodes: ["entry_1"])
      assert {:ok, updated} = InstanceStore.update_current_nodes(instance, ["node_2", "node_3"])
      assert updated.current_nodes == ["node_2", "node_3"]
    end
  end

  describe "complete_instance/1" do
    test "marks instance as completed" do
      instance = insert(:flow_instance)
      assert {:ok, completed} = InstanceStore.complete_instance(instance)
      assert completed.status == "completed"
      assert completed.completed_at != nil
      assert completed.current_nodes == []
    end
  end

  describe "fail_instance/2" do
    test "marks instance as failed with reason" do
      instance = insert(:flow_instance)
      assert {:ok, failed} = InstanceStore.fail_instance(instance, "node crashed")
      assert failed.status == "failed"
      assert failed.exit_reason == "node crashed"
      assert failed.exited_at != nil
    end
  end

  describe "customer_active_in_flow?/2" do
    test "returns false when no instances exist" do
      flow = insert(:flow)
      refute InstanceStore.customer_active_in_flow?(flow.id, "nobody")
    end

    test "returns true for running instance" do
      flow = insert(:flow)

      insert(:flow_instance,
        flow: flow,
        tenant: flow.tenant,
        customer_id: "cust_1",
        status: "running"
      )

      assert InstanceStore.customer_active_in_flow?(flow.id, "cust_1")
    end

    test "returns true for waiting instance" do
      flow = insert(:flow)

      insert(:flow_instance,
        flow: flow,
        tenant: flow.tenant,
        customer_id: "cust_1",
        status: "waiting"
      )

      assert InstanceStore.customer_active_in_flow?(flow.id, "cust_1")
    end

    test "returns false for completed instance" do
      flow = insert(:flow)

      insert(:flow_instance,
        flow: flow,
        tenant: flow.tenant,
        customer_id: "cust_1",
        status: "completed"
      )

      refute InstanceStore.customer_active_in_flow?(flow.id, "cust_1")
    end

    test "returns false for different customer" do
      flow = insert(:flow)

      insert(:flow_instance,
        flow: flow,
        tenant: flow.tenant,
        customer_id: "cust_1",
        status: "running"
      )

      refute InstanceStore.customer_active_in_flow?(flow.id, "cust_2")
    end
  end
end
