defmodule Kalcifer.Bugs.RepublishValidationTest do
  @moduledoc """
  Regression tests for FlowVersion changeset guards (originally I2/I3).
  These bugs have been FIXED:
  - republish_changeset now validates graph
  - rollback_changeset and republish_changeset now have status guards
  """
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Flows.FlowVersion

  test "republish_changeset validates graph (rejects invalid graph)" do
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
    refute changeset.valid?
  end

  test "rollback_changeset rejects draft version" do
    version = %FlowVersion{
      id: Ecto.UUID.generate(),
      version_number: 1,
      graph: %{},
      status: "draft"
    }

    changeset = FlowVersion.rollback_changeset(version)
    refute changeset.valid?
  end

  test "republish_changeset rejects draft version" do
    version = %FlowVersion{
      id: Ecto.UUID.generate(),
      version_number: 1,
      graph: valid_graph(),
      status: "draft"
    }

    changeset = FlowVersion.republish_changeset(version)
    refute changeset.valid?
  end

  test "republish_changeset accepts deprecated version with valid graph" do
    version = %FlowVersion{
      id: Ecto.UUID.generate(),
      version_number: 1,
      graph: valid_graph(),
      status: "deprecated"
    }

    changeset = FlowVersion.republish_changeset(version)
    assert changeset.valid?
  end

  test "rollback_changeset accepts published version" do
    version = %FlowVersion{
      id: Ecto.UUID.generate(),
      version_number: 1,
      graph: valid_graph(),
      status: "published"
    }

    changeset = FlowVersion.rollback_changeset(version)
    assert changeset.valid?
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
