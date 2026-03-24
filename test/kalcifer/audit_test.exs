defmodule Kalcifer.AuditTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Audit

  setup do
    {:ok, tenant} =
      Kalcifer.Tenants.create_tenant(%{
        name: "audit-test-#{System.unique_integer([:positive])}",
        api_key_hash: Kalcifer.Tenants.hash_api_key("audit-test-key-#{System.unique_integer()}")
      })

    %{tenant_id: tenant.id}
  end

  describe "log/2" do
    test "creates an audit entry", %{tenant_id: tid} do
      assert {:ok, entry} =
               Audit.log(tid, %{
                 actor: "api",
                 action: "create",
                 resource_type: "flow",
                 resource_id: "flow-123",
                 details: %{name: "Test Flow"}
               })

      assert entry.actor == "api"
      assert entry.action == "create"
      assert entry.resource_type == "flow"
      assert entry.resource_id == "flow-123"
      # Details uses atom keys on insert, but maps are stored as-is
      assert entry.details[:name] == "Test Flow" || entry.details["name"] == "Test Flow"
    end

    test "requires actor, action, resource_type", %{tenant_id: tid} do
      assert {:error, _} = Audit.log(tid, %{actor: "api"})
    end
  end

  describe "list/2" do
    test "returns entries newest first", %{tenant_id: tid} do
      Audit.log(tid, %{actor: "a", action: "first", resource_type: "flow"})
      Audit.log(tid, %{actor: "a", action: "second", resource_type: "flow"})

      entries = Audit.list(tid)
      assert length(entries) == 2
      assert hd(entries).action == "second"
    end

    test "filters by resource_type", %{tenant_id: tid} do
      Audit.log(tid, %{actor: "a", action: "x", resource_type: "flow"})
      Audit.log(tid, %{actor: "a", action: "y", resource_type: "tenant"})

      assert [entry] = Audit.list(tid, resource_type: "flow")
      assert entry.resource_type == "flow"
    end

    test "respects limit and offset", %{tenant_id: tid} do
      for i <- 1..5 do
        Audit.log(tid, %{actor: "a", action: "a#{i}", resource_type: "flow"})
      end

      assert length(Audit.list(tid, limit: 2)) == 2
      assert length(Audit.list(tid, limit: 2, offset: 4)) == 1
    end
  end

  describe "for_resource/3" do
    test "returns entries for specific resource", %{tenant_id: tid} do
      Audit.log(tid, %{actor: "a", action: "x", resource_type: "flow", resource_id: "f1"})
      Audit.log(tid, %{actor: "a", action: "y", resource_type: "flow", resource_id: "f2"})

      entries = Audit.for_resource("flow", "f1")
      assert length(entries) == 1
      assert hd(entries).resource_id == "f1"
    end
  end
end
