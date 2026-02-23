defmodule Kalcifer.Bugs.InstanceStatusTransitionTest do
  @moduledoc """
  I1: FlowInstance.status_changeset does not validate state machine transitions.
  Unlike Flow which validates transitions (draft → active → paused → archived),
  FlowInstance allows any status → any status, including completed → running.
  """
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Flows.FlowInstance

  @tag :known_bug
  test "status_changeset should reject completed → running transition" do
    instance = %FlowInstance{
      id: Ecto.UUID.generate(),
      status: "completed",
      version_number: 1,
      customer_id: "test"
    }

    changeset = FlowInstance.status_changeset(instance, "running")

    # BUG: Currently this changeset is valid — no transition validation.
    # A completed instance should NOT be allowed to go back to running.
    refute changeset.valid?,
           "BUG: FlowInstance allows completed → running transition without validation"
  end

  @tag :known_bug
  test "status_changeset should reject failed → completed transition" do
    instance = %FlowInstance{
      id: Ecto.UUID.generate(),
      status: "failed",
      version_number: 1,
      customer_id: "test"
    }

    changeset = FlowInstance.status_changeset(instance, "completed")

    refute changeset.valid?,
           "BUG: FlowInstance allows failed → completed transition without validation"
  end

  @tag :known_bug
  test "status_changeset should reject exited → running transition" do
    instance = %FlowInstance{
      id: Ecto.UUID.generate(),
      status: "exited",
      version_number: 1,
      customer_id: "test"
    }

    changeset = FlowInstance.status_changeset(instance, "running")

    refute changeset.valid?,
           "BUG: FlowInstance allows exited → running transition without validation"
  end
end
