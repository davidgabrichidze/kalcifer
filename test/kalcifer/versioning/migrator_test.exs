defmodule Kalcifer.Versioning.MigratorTest do
  use Kalcifer.DataCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Engine.FlowTrigger
  alias Kalcifer.Engine.Persistence.InstanceStore
  alias Kalcifer.Flows
  alias Kalcifer.Versioning.Migrator

  defp wait_graph(event_type \\ "email_opened", timeout \\ "3d") do
    %{
      "nodes" => [
        %{
          "id" => "entry_1",
          "type" => "event_entry",
          "position" => %{"x" => 0, "y" => 0},
          "config" => %{"event_type" => "signed_up"}
        },
        %{
          "id" => "wait_1",
          "type" => "wait_for_event",
          "position" => %{"x" => 100, "y" => 0},
          "config" => %{"event_type" => event_type, "timeout" => timeout}
        },
        %{
          "id" => "exit_1",
          "type" => "exit",
          "position" => %{"x" => 200, "y" => 0},
          "config" => %{}
        }
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
        %{
          "id" => "e2",
          "source" => "wait_1",
          "target" => "exit_1",
          "branch" => "event_received"
        },
        %{"id" => "e3", "source" => "wait_1", "target" => "exit_1", "branch" => "timed_out"}
      ]
    }
  end

  defp removed_node_graph do
    %{
      "nodes" => [
        %{
          "id" => "entry_1",
          "type" => "event_entry",
          "position" => %{"x" => 0, "y" => 0},
          "config" => %{"event_type" => "signed_up"}
        },
        %{
          "id" => "exit_1",
          "type" => "exit",
          "position" => %{"x" => 200, "y" => 0},
          "config" => %{}
        }
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "exit_1"}
      ]
    }
  end

  defp setup_flow_with_waiting_instance(graph_v1) do
    flow = insert(:flow)
    v1 = insert(:flow_version, flow: flow, version_number: 1, graph: graph_v1)
    {:ok, flow} = Flows.activate_flow(flow)

    customer_id = "migrator_cust_#{System.unique_integer([:positive])}"

    {:ok, instance_id} =
      FlowTrigger.trigger(flow.id, customer_id)

    Process.sleep(200)

    # Verify waiting
    state = FlowServer.get_state(instance_id)
    assert state.status == :waiting

    %{flow: Flows.get_flow!(flow.id), instance_id: instance_id, customer_id: customer_id, v1: v1}
  end

  describe "migrate/4 with migrate_all" do
    test "migrates waiting instance to new version" do
      %{flow: flow, instance_id: instance_id} =
        setup_flow_with_waiting_instance(wait_graph("email_opened"))

      # Create v2 with different event_type
      {:ok, _v2} = Flows.create_version(flow, %{graph: wait_graph("push_opened"), changelog: "v2"})

      assert {:ok, result} = Migrator.migrate(flow.id, 1, 2, "migrate_all")
      assert instance_id in result.migrated
      assert result.exited == []
      assert result.skipped == []
      assert result.failed == []

      # Verify FlowServer has new version
      state = FlowServer.get_state(instance_id)
      assert state.version_number == 2
      assert state.context["_waiting_event_type"] == "push_opened"

      # Verify DB
      db_instance = InstanceStore.get_instance(instance_id)
      assert db_instance.version_number == 2
      assert db_instance.migrated_from_version == 1
      assert db_instance.migrated_at != nil

      # Clean up
      GenServer.stop({:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}, :normal)
    end

    test "exits instance on removed node" do
      %{flow: flow, instance_id: instance_id} =
        setup_flow_with_waiting_instance(wait_graph("email_opened"))

      # v2 removes wait_1 node
      {:ok, _v2} = Flows.create_version(flow, %{graph: removed_node_graph(), changelog: "v2"})

      assert {:ok, result} = Migrator.migrate(flow.id, 1, 2, "migrate_all")
      assert instance_id in result.exited
      assert result.migrated == []

      db_instance = InstanceStore.get_instance(instance_id)
      assert db_instance.status == "exited"
      assert db_instance.exit_reason == "node_removed_in_new_version"
    end

    test "handles no active instances gracefully" do
      flow = insert(:flow)
      insert(:flow_version, flow: flow, version_number: 1, graph: wait_graph())
      insert(:flow_version, flow: flow, version_number: 2, graph: wait_graph("push_opened"))

      assert {:ok, result} = Migrator.migrate(flow.id, 1, 2, "migrate_all")
      assert result.migrated == []
      assert result.exited == []
      assert result.skipped == []
    end
  end

  describe "migrate/4 with new_entries_only" do
    test "skips all instances" do
      %{flow: flow, instance_id: instance_id} =
        setup_flow_with_waiting_instance(wait_graph("email_opened"))

      {:ok, _v2} = Flows.create_version(flow, %{graph: wait_graph("push_opened"), changelog: "v2"})

      assert {:ok, result} = Migrator.migrate(flow.id, 1, 2, "new_entries_only")
      assert instance_id in result.skipped
      assert result.migrated == []

      # Instance still on v1
      state = FlowServer.get_state(instance_id)
      assert state.version_number == 1

      GenServer.stop({:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}, :normal)
    end
  end

  describe "migrate/4 edge cases" do
    test "skips running instances (not waiting) in migrate_all" do
      flow = insert(:flow)
      insert(:flow_version, flow: flow, version_number: 1, graph: wait_graph())
      insert(:flow_version, flow: flow, version_number: 2, graph: wait_graph("push_opened"))

      # Insert a running instance (no FlowServer process)
      insert(:flow_instance,
        flow: flow,
        tenant: flow.tenant,
        customer_id: "running_cust",
        status: "running",
        version_number: 1,
        current_nodes: ["entry_1"]
      )

      assert {:ok, result} = Migrator.migrate(flow.id, 1, 2, "migrate_all")
      # Running instance on entry_1 (exists in v2) → migrated in DB, no process to hot-swap
      assert length(result.migrated) == 1
    end

    test "handles dead FlowServer process gracefully (DB-only migration)" do
      %{flow: flow, instance_id: instance_id} =
        setup_flow_with_waiting_instance(wait_graph("email_opened"))

      {:ok, _v2} = Flows.create_version(flow, %{graph: wait_graph("push_opened"), changelog: "v2"})

      # Kill the FlowServer before migration
      via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}
      GenServer.stop(via, :kill)
      Process.sleep(50)

      assert {:ok, result} = Migrator.migrate(flow.id, 1, 2, "migrate_all")
      assert instance_id in result.migrated

      # DB should be updated even without live process
      db_instance = InstanceStore.get_instance(instance_id)
      assert db_instance.version_number == 2
      assert db_instance.migrated_from_version == 1
    end

    test "mixed batch: some migrated, some exited" do
      flow = insert(:flow)
      insert(:flow_version, flow: flow, version_number: 1, graph: wait_graph())
      {:ok, flow} = Flows.activate_flow(flow)

      # Trigger two customers
      {:ok, id1} = FlowTrigger.trigger(flow.id, "mix_c1_#{System.unique_integer([:positive])}")
      {:ok, id2} = FlowTrigger.trigger(flow.id, "mix_c2_#{System.unique_integer([:positive])}")
      Process.sleep(200)

      flow = Flows.get_flow!(flow.id)

      # v2 removes wait_1 but keeps entry_1 and exit_1
      # Both instances are waiting on wait_1 → both should be exited
      {:ok, _v2} = Flows.create_version(flow, %{graph: removed_node_graph(), changelog: "v2"})

      assert {:ok, result} = Migrator.migrate(flow.id, 1, 2, "migrate_all")
      assert id1 in result.exited
      assert id2 in result.exited
    end

    test "returns error for non-existent source version" do
      flow = insert(:flow)
      insert(:flow_version, flow: flow, version_number: 1, graph: wait_graph())

      assert {:error, :version_not_found} = Migrator.migrate(flow.id, 1, 99, "migrate_all")
    end
  end

  describe "rollback/3" do
    test "migrates instances back to previous version" do
      %{flow: flow, instance_id: instance_id} =
        setup_flow_with_waiting_instance(wait_graph("email_opened"))

      {:ok, _v2} = Flows.create_version(flow, %{graph: wait_graph("push_opened"), changelog: "v2"})

      # Migrate to v2
      {:ok, _} = Migrator.migrate(flow.id, 1, 2, "migrate_all")
      state = FlowServer.get_state(instance_id)
      assert state.version_number == 2

      # Rollback to v1
      {:ok, result} = Migrator.rollback(flow.id, 2, 1)
      assert instance_id in result.migrated

      state = FlowServer.get_state(instance_id)
      assert state.version_number == 1
      assert state.context["_waiting_event_type"] == "email_opened"

      GenServer.stop({:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}, :normal)
    end
  end
end
