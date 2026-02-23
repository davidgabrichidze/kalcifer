defmodule Kalcifer.MarketingTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Marketing
  alias Kalcifer.Marketing.Journey

  import Kalcifer.Factory

  describe "create_journey/2" do
    test "creates a journey with valid attributes" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)

      assert {:ok, %Journey{} = journey} =
               Marketing.create_journey(tenant.id, %{
                 name: "Onboarding",
                 flow_id: flow.id
               })

      assert journey.name == "Onboarding"
      assert journey.status == "draft"
      assert journey.tenant_id == tenant.id
      assert journey.flow_id == flow.id
    end

    test "creates a journey with marketing-specific fields" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)

      assert {:ok, %Journey{} = journey} =
               Marketing.create_journey(tenant.id, %{
                 name: "Welcome Series",
                 flow_id: flow.id,
                 goal_config: %{"event" => "first_purchase", "window" => "30d"},
                 schedule: %{"type" => "recurring", "cron" => "0 9 * * 1"},
                 audience_criteria: %{"segment_id" => "new_users"},
                 tags: ["onboarding", "email"]
               })

      assert journey.goal_config == %{"event" => "first_purchase", "window" => "30d"}
      assert journey.schedule == %{"type" => "recurring", "cron" => "0 9 * * 1"}
      assert journey.audience_criteria == %{"segment_id" => "new_users"}
      assert journey.tags == ["onboarding", "email"]
    end

    test "fails without required name" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)

      assert {:error, changeset} =
               Marketing.create_journey(tenant.id, %{flow_id: flow.id})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "get_journey/1" do
    test "returns the journey by id" do
      journey = insert(:journey)
      found = Marketing.get_journey(journey.id)
      assert found.id == journey.id
    end

    test "returns nil for non-existent id" do
      assert Marketing.get_journey(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_journey_with_flow/1" do
    test "returns journey with preloaded flow" do
      journey = insert(:journey)
      found = Marketing.get_journey_with_flow(journey.id)
      assert found.id == journey.id
      assert found.flow != nil
      assert found.flow.id == journey.flow_id
    end
  end

  describe "list_journeys/2" do
    test "returns journeys for a tenant" do
      tenant = insert(:tenant)
      flow1 = insert(:flow, tenant: tenant)
      flow2 = insert(:flow, tenant: tenant)
      insert(:journey, tenant: tenant, flow: flow1, name: "J1")
      insert(:journey, tenant: tenant, flow: flow2, name: "J2")

      other_tenant = insert(:tenant)
      other_flow = insert(:flow, tenant: other_tenant)
      insert(:journey, tenant: other_tenant, flow: other_flow, name: "Other")

      journeys = Marketing.list_journeys(tenant.id)
      assert length(journeys) == 2
    end

    test "filters by status" do
      tenant = insert(:tenant)
      flow1 = insert(:flow, tenant: tenant)
      flow2 = insert(:flow, tenant: tenant)
      insert(:journey, tenant: tenant, flow: flow1, status: "draft")
      insert(:journey, tenant: tenant, flow: flow2, status: "active")

      drafts = Marketing.list_journeys(tenant.id, status: "draft")
      assert length(drafts) == 1
      assert hd(drafts).status == "draft"
    end

    test "filters by tag" do
      tenant = insert(:tenant)
      flow1 = insert(:flow, tenant: tenant)
      flow2 = insert(:flow, tenant: tenant)
      insert(:journey, tenant: tenant, flow: flow1, tags: ["email", "onboarding"])
      insert(:journey, tenant: tenant, flow: flow2, tags: ["sms"])

      email_journeys = Marketing.list_journeys(tenant.id, tag: "email")
      assert length(email_journeys) == 1
    end
  end

  describe "update_journey/2" do
    test "updates a draft journey" do
      journey = insert(:journey, status: "draft")

      assert {:ok, updated} =
               Marketing.update_journey(journey, %{name: "Updated Name"})

      assert updated.name == "Updated Name"
    end

    test "rejects update on non-draft journey" do
      journey = insert(:journey, status: "active")
      assert {:error, :journey_not_draft} = Marketing.update_journey(journey, %{name: "Nope"})
    end
  end

  describe "delete_journey/1" do
    test "deletes a draft journey" do
      journey = insert(:journey, status: "draft")
      assert {:ok, _} = Marketing.delete_journey(journey)
      assert Marketing.get_journey(journey.id) == nil
    end

    test "rejects delete on non-draft journey" do
      journey = insert(:journey, status: "active")
      assert {:error, :journey_not_draft} = Marketing.delete_journey(journey)
    end
  end

  describe "launch_journey/1" do
    test "activates underlying flow and sets journey to active" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant, status: "draft")
      insert(:flow_version, flow: flow, version_number: 1, status: "draft")
      journey = insert(:journey, tenant: tenant, flow: flow, status: "draft")

      assert {:ok, launched} = Marketing.launch_journey(journey)
      assert launched.status == "active"
    end

    test "fails when flow has no draft version" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant, status: "draft")
      journey = insert(:journey, tenant: tenant, flow: flow, status: "draft")

      assert {:error, :no_draft_version} = Marketing.launch_journey(journey)
    end
  end

  describe "pause_journey/1" do
    test "pauses an active journey" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant, status: "active")
      journey = insert(:journey, tenant: tenant, flow: flow, status: "active")

      assert {:ok, paused} = Marketing.pause_journey(journey)
      assert paused.status == "paused"
    end
  end

  describe "resume_journey/1" do
    test "resumes a paused journey" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant, status: "paused")
      journey = insert(:journey, tenant: tenant, flow: flow, status: "paused")

      assert {:ok, resumed} = Marketing.resume_journey(journey)
      assert resumed.status == "active"
    end
  end

  describe "archive_journey/1" do
    test "archives an active journey" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant, status: "active")
      journey = insert(:journey, tenant: tenant, flow: flow, status: "active")

      assert {:ok, archived} = Marketing.archive_journey(journey)
      assert archived.status == "archived"
    end
  end

  describe "lifecycle edge cases" do
    test "launch_journey rejects already-active journey" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant, status: "draft")
      insert(:flow_version, flow: flow, version_number: 1, status: "draft")
      journey = insert(:journey, tenant: tenant, flow: flow, status: "draft")
      {:ok, journey} = Marketing.launch_journey(journey)

      assert {:error, :no_draft_version} = Marketing.launch_journey(journey)
    end

    test "pause_journey rejects draft journey" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant, status: "draft")
      journey = insert(:journey, tenant: tenant, flow: flow, status: "draft")

      assert {:error, _reason} = Marketing.pause_journey(journey)
    end

    test "archive_journey rejects draft journey" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant, status: "draft")
      journey = insert(:journey, tenant: tenant, flow: flow, status: "draft")

      assert {:error, _reason} = Marketing.archive_journey(journey)
    end
  end

  describe "cascade constraints" do
    test "cannot delete a flow that has journeys (on_delete: :restrict)" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)
      _journey = insert(:journey, tenant: tenant, flow: flow)

      assert_raise Ecto.ConstraintError, fn ->
        Kalcifer.Repo.delete!(flow)
      end
    end

    test "can delete a flow after its journeys are removed" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)
      journey = insert(:journey, tenant: tenant, flow: flow)

      {:ok, _} = Kalcifer.Repo.delete(journey)
      assert {:ok, _} = Kalcifer.Repo.delete(flow)
    end
  end
end
