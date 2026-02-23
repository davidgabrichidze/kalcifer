defmodule Kalcifer.Bugs.RollbackInvalidTargetTest do
  @moduledoc """
  P1: Rollback to non-republishable version crashes with 500.

  When rollback target has a status that republish_changeset rejects
  (e.g. draft, or the currently published version), Repo.update! raises
  Ecto.InvalidChangesetError. The safe_update! guard should catch this
  and return a clean {:error, {:invalid_changeset, changeset}} instead.
  """
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Flows

  describe "rollback_flow_version/2 with invalid targets" do
    test "rollback to a draft version returns error, not crash" do
      flow = insert(:flow)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())
      {:ok, flow} = Flows.activate_flow(flow)

      # Create v2 as draft (never published)
      {:ok, _v2} = Flows.create_version(flow, %{graph: valid_graph(), changelog: "v2 draft"})

      # Rollback to draft v2 — republish_changeset rejects "draft" status
      result = Flows.rollback_flow_version(Flows.get_flow!(flow.id), 2)

      assert {:error, {:invalid_changeset, changeset}} = result
      assert %{status: _} = errors_on(changeset)
    end

    test "rollback to the currently active version returns error, not crash" do
      flow = insert(:flow)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())
      {:ok, flow} = Flows.activate_flow(flow)

      # Rollback to v1 which is currently published (active)
      # republish_changeset rejects "published" status
      result = Flows.rollback_flow_version(Flows.get_flow!(flow.id), 1)

      assert {:error, {:invalid_changeset, changeset}} = result
      assert %{status: _} = errors_on(changeset)
    end

    test "rollback does not leave DB in partial state on changeset failure" do
      flow = insert(:flow)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())
      {:ok, flow} = Flows.activate_flow(flow)

      {:ok, _v2} = Flows.create_version(flow, %{graph: valid_graph(), changelog: "v2 draft"})

      # Attempt rollback to draft — should fail
      {:error, {:invalid_changeset, _}} =
        Flows.rollback_flow_version(Flows.get_flow!(flow.id), 2)

      # Verify v1 is still published (transaction rolled back)
      v1 = Flows.get_version(flow.id, 1)
      assert v1.status == "published"

      # Verify flow still points to v1
      reloaded = Flows.get_flow!(flow.id)
      assert reloaded.active_version_id == v1.id
    end
  end
end
