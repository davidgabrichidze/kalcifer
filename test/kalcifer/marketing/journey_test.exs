defmodule Kalcifer.Marketing.JourneyTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Marketing.Journey

  describe "create_changeset/2" do
    test "valid with required fields" do
      changeset =
        Journey.create_changeset(%Journey{}, %{
          name: "Onboarding Journey",
          tenant_id: Ecto.UUID.generate(),
          flow_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == "draft"
    end

    test "invalid without name" do
      changeset =
        Journey.create_changeset(%Journey{}, %{
          tenant_id: Ecto.UUID.generate(),
          flow_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without tenant_id" do
      changeset =
        Journey.create_changeset(%Journey{}, %{
          name: "Test",
          flow_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert %{tenant_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without flow_id" do
      changeset =
        Journey.create_changeset(%Journey{}, %{
          name: "Test",
          tenant_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert %{flow_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "accepts optional marketing fields" do
      changeset =
        Journey.create_changeset(%Journey{}, %{
          name: "Test",
          tenant_id: Ecto.UUID.generate(),
          flow_id: Ecto.UUID.generate(),
          goal_config: %{"event" => "purchase"},
          schedule: %{"type" => "one_time"},
          audience_criteria: %{"segment_id" => "seg_1"},
          tags: ["onboarding", "email"]
        })

      assert changeset.valid?
    end
  end

  describe "update_changeset/2" do
    test "updates allowed fields" do
      journey = %Journey{name: "Old Name", status: "draft"}

      changeset =
        Journey.update_changeset(journey, %{
          name: "New Name",
          goal_config: %{"event" => "purchase"}
        })

      assert changeset.valid?
      assert get_change(changeset, :name) == "New Name"
    end

    test "requires name" do
      journey = %Journey{name: "Old Name", status: "draft"}
      changeset = Journey.update_changeset(journey, %{name: nil})
      refute changeset.valid?
    end
  end

  describe "status_changeset/2" do
    test "valid transition draft -> active" do
      journey = %Journey{status: "draft"}
      changeset = Journey.status_changeset(journey, "active")
      assert changeset.valid?
    end

    test "invalid transition draft -> paused" do
      journey = %Journey{status: "draft"}
      changeset = Journey.status_changeset(journey, "paused")
      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end

    test "valid transition active -> paused" do
      journey = %Journey{status: "active"}
      changeset = Journey.status_changeset(journey, "paused")
      assert changeset.valid?
    end

    test "valid transition active -> archived" do
      journey = %Journey{status: "active"}
      changeset = Journey.status_changeset(journey, "archived")
      assert changeset.valid?
    end

    test "valid transition paused -> active" do
      journey = %Journey{status: "paused"}
      changeset = Journey.status_changeset(journey, "active")
      assert changeset.valid?
    end

    test "no transitions from archived" do
      journey = %Journey{status: "archived"}
      changeset = Journey.status_changeset(journey, "active")
      refute changeset.valid?
    end
  end
end
