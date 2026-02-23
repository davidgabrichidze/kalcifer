defmodule Kalcifer.FlowsTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Flows
  alias Kalcifer.Flows.Flow
  alias Kalcifer.Flows.FlowVersion

  import Kalcifer.Factory

  describe "create_flow/2" do
    test "creates a flow with valid attributes" do
      tenant = insert(:tenant)

      assert {:ok, %Flow{} = flow} =
               Flows.create_flow(tenant.id, %{name: "Onboarding"})

      assert flow.name == "Onboarding"
      assert flow.status == "draft"
      assert flow.tenant_id == tenant.id
    end

    test "fails without required name" do
      tenant = insert(:tenant)

      assert {:error, changeset} = Flows.create_flow(tenant.id, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "get_flow/1" do
    test "returns the flow by id" do
      flow = insert(:flow)
      assert found = Flows.get_flow(flow.id)
      assert found.id == flow.id
    end

    test "returns nil for non-existent id" do
      assert Flows.get_flow(Ecto.UUID.generate()) == nil
    end
  end

  describe "list_flows/2" do
    test "returns flows for a tenant" do
      tenant = insert(:tenant)
      insert(:flow, tenant: tenant, name: "F1")
      insert(:flow, tenant: tenant, name: "F2")
      insert(:flow, name: "Other tenant flow")

      flows = Flows.list_flows(tenant.id)
      assert length(flows) == 2
    end

    test "filters by status" do
      tenant = insert(:tenant)
      insert(:flow, tenant: tenant, status: "draft")
      insert(:flow, tenant: tenant, status: "active")

      drafts = Flows.list_flows(tenant.id, status: "draft")
      assert length(drafts) == 1
      assert hd(drafts).status == "draft"
    end
  end

  describe "update_flow/2" do
    test "updates a draft flow" do
      flow = insert(:flow, status: "draft")

      assert {:ok, updated} = Flows.update_flow(flow, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "rejects update on non-draft flow" do
      flow = insert(:flow, status: "active")
      assert {:error, :not_draft} = Flows.update_flow(flow, %{name: "Nope"})
    end
  end

  describe "delete_flow/1" do
    test "deletes a draft flow" do
      flow = insert(:flow, status: "draft")
      assert {:ok, _} = Flows.delete_flow(flow)
      assert Flows.get_flow(flow.id) == nil
    end

    test "rejects delete on non-draft flow" do
      flow = insert(:flow, status: "active")
      assert {:error, :not_draft} = Flows.delete_flow(flow)
    end
  end

  describe "lifecycle transitions" do
    test "activate_flow publishes draft version and sets status to active" do
      flow = insert(:flow, status: "draft")
      insert(:flow_version, flow: flow, version_number: 1, status: "draft")

      assert {:ok, activated} = Flows.activate_flow(flow)
      assert activated.status == "active"
      assert activated.active_version_id != nil
    end

    test "activate_flow fails without a draft version" do
      flow = insert(:flow, status: "draft")
      assert {:error, :no_draft_version} = Flows.activate_flow(flow)
    end

    test "pause_flow transitions active → paused" do
      flow = insert(:flow, status: "active")
      assert {:ok, paused} = Flows.pause_flow(flow)
      assert paused.status == "paused"
    end

    test "pause_flow rejects invalid transition from draft" do
      flow = insert(:flow, status: "draft")
      assert {:error, changeset} = Flows.pause_flow(flow)
      assert %{status: _} = errors_on(changeset)
    end

    test "resume_flow transitions paused → active" do
      flow = insert(:flow, status: "paused")
      assert {:ok, resumed} = Flows.resume_flow(flow)
      assert resumed.status == "active"
    end

    test "archive_flow transitions active → archived" do
      flow = insert(:flow, status: "active")
      assert {:ok, archived} = Flows.archive_flow(flow)
      assert archived.status == "archived"
    end

    test "archive_flow transitions paused → archived" do
      flow = insert(:flow, status: "paused")
      assert {:ok, archived} = Flows.archive_flow(flow)
      assert archived.status == "archived"
    end

    test "resume_flow rejects archived flow" do
      flow = insert(:flow, status: "archived")
      assert {:error, changeset} = Flows.resume_flow(flow)
      assert %{status: _} = errors_on(changeset)
    end

    test "archive_flow rejects draft flow" do
      flow = insert(:flow, status: "draft")
      assert {:error, changeset} = Flows.archive_flow(flow)
      assert %{status: _} = errors_on(changeset)
    end

    test "activate_flow rejects when no draft version exists on active flow" do
      flow = insert(:flow, status: "draft")
      insert(:flow_version, flow: flow, version_number: 1, status: "draft")
      {:ok, active_flow} = Flows.activate_flow(flow)

      assert {:error, :no_draft_version} = Flows.activate_flow(active_flow)
    end

    test "activate_flow with invalid graph rolls back transaction" do
      flow = insert(:flow, status: "draft")

      bad_graph = %{
        "nodes" => [%{"id" => "x", "type" => "send_email", "config" => %{}}],
        "edges" => []
      }

      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: bad_graph)

      assert {:error, _} = Flows.activate_flow(flow)

      reloaded = Flows.get_flow(flow.id)
      assert reloaded.status == "draft"
    end
  end

  describe "version management" do
    test "create_version auto-increments version number" do
      flow = insert(:flow)

      assert {:ok, v1} = Flows.create_version(flow, %{graph: valid_graph()})
      assert v1.version_number == 1

      assert {:ok, v2} = Flows.create_version(flow, %{graph: valid_graph()})
      assert v2.version_number == 2
    end

    test "get_version returns by flow_id and version_number" do
      flow = insert(:flow)
      {:ok, v1} = Flows.create_version(flow, %{graph: valid_graph()})

      assert found = Flows.get_version(flow.id, 1)
      assert found.id == v1.id
    end

    test "list_versions returns all versions ordered by number" do
      flow = insert(:flow)
      Flows.create_version(flow, %{graph: valid_graph(), changelog: "v1"})
      Flows.create_version(flow, %{graph: valid_graph(), changelog: "v2"})

      versions = Flows.list_versions(flow.id)
      assert length(versions) == 2
      assert [%{version_number: 1}, %{version_number: 2}] = versions
    end

    test "publish_version validates graph and sets published status" do
      flow = insert(:flow)
      {:ok, version} = Flows.create_version(flow, %{graph: valid_graph()})

      assert {:ok, %FlowVersion{} = published} = Flows.publish_version(version)
      assert published.status == "published"
      assert published.published_at != nil
    end

    test "publish_version rejects invalid graph" do
      flow = insert(:flow)
      # Graph with no entry node
      bad_graph = %{
        "nodes" => [%{"id" => "x", "type" => "send_email", "config" => %{}}],
        "edges" => []
      }

      {:ok, version} = Flows.create_version(flow, %{graph: bad_graph})

      assert {:error, changeset} = Flows.publish_version(version)
      assert %{graph: _} = errors_on(changeset)
    end

    test "publish_version rejects already-published version" do
      version = insert(:flow_version, status: "published")
      assert {:error, :not_draft} = Flows.publish_version(version)
    end
  end

  describe "migrate_flow_version/3" do
    test "returns error when target version does not exist" do
      flow = insert(:flow)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())
      {:ok, flow} = Flows.activate_flow(flow)

      assert {:error, :version_not_found} = Flows.migrate_flow_version(flow, 99)
    end

    test "returns error when flow has no active version" do
      flow = insert(:flow, status: "draft", active_version_id: nil)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())

      assert {:error, :no_active_version} = Flows.migrate_flow_version(flow, 1)
    end
  end

  describe "rollback_flow_version/2" do
    test "returns error when flow has no active version" do
      flow = insert(:flow, status: "draft", active_version_id: nil)
      assert {:error, :no_active_version} = Flows.rollback_flow_version(flow, 1)
    end

    test "returns error when target version does not exist" do
      flow = insert(:flow)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())
      {:ok, flow} = Flows.activate_flow(flow)

      assert {:error, :version_not_found} = Flows.rollback_flow_version(flow, 99)
    end
  end

  describe "migration_status/1" do
    test "returns instance counts grouped by version" do
      flow = insert(:flow)

      insert(:flow_instance,
        flow: flow,
        tenant: flow.tenant,
        customer_id: "c1",
        status: "waiting",
        version_number: 1
      )

      insert(:flow_instance,
        flow: flow,
        tenant: flow.tenant,
        customer_id: "c2",
        status: "running",
        version_number: 2
      )

      insert(:flow_instance,
        flow: flow,
        tenant: flow.tenant,
        customer_id: "c3",
        status: "completed",
        version_number: 1
      )

      status = Flows.migration_status(flow.id)
      assert status[1] == 1
      assert status[2] == 1
      refute Map.has_key?(status, 3)
    end

    test "returns empty map when no active instances" do
      flow = insert(:flow)
      assert Flows.migration_status(flow.id) == %{}
    end
  end
end
