defmodule Kalcifer.Bugs.InstanceStatusTransitionTest do
  @moduledoc """
  I1: Regression test for FlowInstance state machine transitions.
  FlowInstance.status_changeset validates transitions via @valid_transitions MapSet.
  Terminal states (completed, failed, exited) have no outgoing transitions.
  """
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Flows.FlowInstance

  test "status_changeset should reject completed → running transition" do
    instance = %FlowInstance{
      id: Ecto.UUID.generate(),
      status: "completed",
      version_number: 1,
      customer_id: "test"
    }

    changeset = FlowInstance.status_changeset(instance, "running")

    refute changeset.valid?
  end

  test "status_changeset should reject failed → completed transition" do
    instance = %FlowInstance{
      id: Ecto.UUID.generate(),
      status: "failed",
      version_number: 1,
      customer_id: "test"
    }

    changeset = FlowInstance.status_changeset(instance, "completed")

    refute changeset.valid?
  end

  test "status_changeset should reject exited → running transition" do
    instance = %FlowInstance{
      id: Ecto.UUID.generate(),
      status: "exited",
      version_number: 1,
      customer_id: "test"
    }

    changeset = FlowInstance.status_changeset(instance, "running")

    refute changeset.valid?
  end
end
