defmodule Kalcifer.Bugs.RepublishValidationTest do
  @moduledoc """
  I2: FlowVersion.republish_changeset skips graph validation.
  publish_changeset validates the graph, but republish_changeset does not.
  A version with an invalid graph can be republished and become the active version.

  I3: rollback_changeset and republish_changeset have no status guards.
  Any version status can be rolled back or republished regardless of current status.
  """
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Flows.FlowVersion

  @tag :known_bug
  test "republish_changeset should validate graph like publish_changeset does" do
    # Create a version with an invalid graph (no entry node)
    bad_graph = %{
      "nodes" => [%{"id" => "x", "type" => "send_email", "config" => %{}}],
      "edges" => []
    }

    version = %FlowVersion{
      id: Ecto.UUID.generate(),
      version_number: 1,
      graph: bad_graph,
      status: "deprecated"
    }

    changeset = FlowVersion.republish_changeset(version)

    # BUG: republish_changeset does NOT call validate_graph.
    # This changeset should be invalid because the graph has no entry node.
    refute changeset.valid?,
           "BUG: republish_changeset accepted invalid graph without validation"
  end

  @tag :known_bug
  test "rollback_changeset should reject draft version (never was published)" do
    version = %FlowVersion{
      id: Ecto.UUID.generate(),
      version_number: 1,
      graph: %{},
      status: "draft"
    }

    changeset = FlowVersion.rollback_changeset(version)

    # BUG: rollback_changeset has no status guard.
    # A draft version was never published, so rolling it back is semantically wrong.
    refute changeset.valid?,
           "BUG: rollback_changeset accepted a draft version — should only accept published/deprecated"
  end

  @tag :known_bug
  test "republish_changeset should reject draft version (never was published)" do
    version = %FlowVersion{
      id: Ecto.UUID.generate(),
      version_number: 1,
      graph: valid_graph(),
      status: "draft"
    }

    changeset = FlowVersion.republish_changeset(version)

    # BUG: republish_changeset has no status guard.
    # A draft version should not be republished — it was never published.
    refute changeset.valid?,
           "BUG: republish_changeset accepted a draft version — should only accept deprecated/rolled_back"
  end

  defp valid_graph do
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
end
