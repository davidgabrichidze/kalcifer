defmodule Kalcifer.JourneysTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Journeys
  alias Kalcifer.Journeys.Journey
  alias Kalcifer.Journeys.JourneyVersion

  import Kalcifer.Factory

  describe "create_journey/2" do
    test "creates a journey with valid attributes" do
      tenant = insert(:tenant)

      assert {:ok, %Journey{} = journey} =
               Journeys.create_journey(tenant.id, %{name: "Onboarding"})

      assert journey.name == "Onboarding"
      assert journey.status == "draft"
      assert journey.tenant_id == tenant.id
    end

    test "fails without required name" do
      tenant = insert(:tenant)

      assert {:error, changeset} = Journeys.create_journey(tenant.id, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "get_journey/1" do
    test "returns the journey by id" do
      journey = insert(:journey)
      assert found = Journeys.get_journey(journey.id)
      assert found.id == journey.id
    end

    test "returns nil for non-existent id" do
      assert Journeys.get_journey(Ecto.UUID.generate()) == nil
    end
  end

  describe "list_journeys/2" do
    test "returns journeys for a tenant" do
      tenant = insert(:tenant)
      insert(:journey, tenant: tenant, name: "J1")
      insert(:journey, tenant: tenant, name: "J2")
      insert(:journey, name: "Other tenant journey")

      journeys = Journeys.list_journeys(tenant.id)
      assert length(journeys) == 2
    end

    test "filters by status" do
      tenant = insert(:tenant)
      insert(:journey, tenant: tenant, status: "draft")
      insert(:journey, tenant: tenant, status: "active")

      drafts = Journeys.list_journeys(tenant.id, status: "draft")
      assert length(drafts) == 1
      assert hd(drafts).status == "draft"
    end
  end

  describe "update_journey/2" do
    test "updates a draft journey" do
      journey = insert(:journey, status: "draft")

      assert {:ok, updated} = Journeys.update_journey(journey, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "rejects update on non-draft journey" do
      journey = insert(:journey, status: "active")
      assert {:error, :not_draft} = Journeys.update_journey(journey, %{name: "Nope"})
    end
  end

  describe "delete_journey/1" do
    test "deletes a draft journey" do
      journey = insert(:journey, status: "draft")
      assert {:ok, _} = Journeys.delete_journey(journey)
      assert Journeys.get_journey(journey.id) == nil
    end

    test "rejects delete on non-draft journey" do
      journey = insert(:journey, status: "active")
      assert {:error, :not_draft} = Journeys.delete_journey(journey)
    end
  end

  describe "lifecycle transitions" do
    test "activate_journey publishes draft version and sets status to active" do
      journey = insert(:journey, status: "draft")
      insert(:journey_version, journey: journey, version_number: 1, status: "draft")

      assert {:ok, activated} = Journeys.activate_journey(journey)
      assert activated.status == "active"
      assert activated.active_version_id != nil
    end

    test "activate_journey fails without a draft version" do
      journey = insert(:journey, status: "draft")
      assert {:error, :no_draft_version} = Journeys.activate_journey(journey)
    end

    test "pause_journey transitions active → paused" do
      journey = insert(:journey, status: "active")
      assert {:ok, paused} = Journeys.pause_journey(journey)
      assert paused.status == "paused"
    end

    test "pause_journey rejects invalid transition from draft" do
      journey = insert(:journey, status: "draft")
      assert {:error, changeset} = Journeys.pause_journey(journey)
      assert %{status: _} = errors_on(changeset)
    end

    test "resume_journey transitions paused → active" do
      journey = insert(:journey, status: "paused")
      assert {:ok, resumed} = Journeys.resume_journey(journey)
      assert resumed.status == "active"
    end

    test "archive_journey transitions active → archived" do
      journey = insert(:journey, status: "active")
      assert {:ok, archived} = Journeys.archive_journey(journey)
      assert archived.status == "archived"
    end

    test "archive_journey transitions paused → archived" do
      journey = insert(:journey, status: "paused")
      assert {:ok, archived} = Journeys.archive_journey(journey)
      assert archived.status == "archived"
    end
  end

  describe "version management" do
    test "create_version auto-increments version number" do
      journey = insert(:journey)

      assert {:ok, v1} = Journeys.create_version(journey, %{graph: valid_graph()})
      assert v1.version_number == 1

      assert {:ok, v2} = Journeys.create_version(journey, %{graph: valid_graph()})
      assert v2.version_number == 2
    end

    test "get_version returns by journey_id and version_number" do
      journey = insert(:journey)
      {:ok, v1} = Journeys.create_version(journey, %{graph: valid_graph()})

      assert found = Journeys.get_version(journey.id, 1)
      assert found.id == v1.id
    end

    test "list_versions returns all versions ordered by number" do
      journey = insert(:journey)
      Journeys.create_version(journey, %{graph: valid_graph(), changelog: "v1"})
      Journeys.create_version(journey, %{graph: valid_graph(), changelog: "v2"})

      versions = Journeys.list_versions(journey.id)
      assert length(versions) == 2
      assert [%{version_number: 1}, %{version_number: 2}] = versions
    end

    test "publish_version validates graph and sets published status" do
      journey = insert(:journey)
      {:ok, version} = Journeys.create_version(journey, %{graph: valid_graph()})

      assert {:ok, %JourneyVersion{} = published} = Journeys.publish_version(version)
      assert published.status == "published"
      assert published.published_at != nil
    end

    test "publish_version rejects invalid graph" do
      journey = insert(:journey)
      # Graph with no entry node
      bad_graph = %{
        "nodes" => [%{"id" => "x", "type" => "send_email", "config" => %{}}],
        "edges" => []
      }

      {:ok, version} = Journeys.create_version(journey, %{graph: bad_graph})

      assert {:error, changeset} = Journeys.publish_version(version)
      assert %{graph: _} = errors_on(changeset)
    end

    test "publish_version rejects already-published version" do
      version = insert(:journey_version, status: "published")
      assert {:error, :not_draft} = Journeys.publish_version(version)
    end
  end
end
