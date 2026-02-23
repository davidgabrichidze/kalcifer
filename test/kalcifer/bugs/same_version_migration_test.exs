defmodule Kalcifer.Bugs.SameVersionMigrationTest do
  @moduledoc """
  T5: Regression test for same-version migration.
  Flows.migrate_flow_version returns {:error, :same_version} when target
  version equals the currently active version.
  """
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Flows

  test "migrate_flow_version to same active version returns :same_version error" do
    flow = insert(:flow)
    insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())
    {:ok, flow} = Flows.activate_flow(flow)

    # Migrate to version 1 which is already active
    result = Flows.migrate_flow_version(flow, 1)

    assert {:error, :same_version} = result
  end
end
