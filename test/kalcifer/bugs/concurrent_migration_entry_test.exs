defmodule Kalcifer.Bugs.ConcurrentMigrationEntryTest do
  @moduledoc """
  BUG-022: Concurrent migration + new entry.

  When a new customer enters a flow while migration is in progress,
  they should get the correct (new) version, not the old one.
  This test verifies version_number consistency after migration.
  """
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Engine.Persistence.InstanceStore
  alias Kalcifer.Flows

  import Kalcifer.Factory

  describe "BUG-022: new entry during migration gets correct version" do
    test "instance created after migration uses new version number" do
      flow = insert(:flow)
      tenant = flow.tenant

      # Create and activate v1
      {:ok, _v1} = Flows.create_version(flow, %{graph: valid_graph()})
      {:ok, flow} = Flows.activate_flow(flow)

      # Create a running instance on v1
      {:ok, old_instance} =
        InstanceStore.create_instance(%{
          flow_id: flow.id,
          version_number: 1,
          customer_id: "existing_cust",
          tenant_id: tenant.id,
          current_nodes: ["entry_1"]
        })

      assert old_instance.version_number == 1

      # Create v2 and migrate
      {:ok, _v2} = Flows.create_version(flow, %{graph: valid_graph()})
      flow = Flows.get_flow(flow.id)
      Flows.migrate_flow_version(flow, 2, "new_entries_only")

      # New instance created AFTER migration should use v2
      {:ok, new_instance} =
        InstanceStore.create_instance(%{
          flow_id: flow.id,
          version_number: 2,
          customer_id: "new_cust",
          tenant_id: tenant.id,
          current_nodes: ["entry_1"]
        })

      assert new_instance.version_number == 2

      # Old instance should still be on v1
      old_reloaded = InstanceStore.get_instance(old_instance.id)
      assert old_reloaded.version_number == 1
    end
  end
end
