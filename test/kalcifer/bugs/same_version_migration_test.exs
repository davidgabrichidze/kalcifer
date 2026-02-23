defmodule Kalcifer.Bugs.SameVersionMigrationTest do
  @moduledoc """
  T5: validate_versions returns {:error, :same_version} when migrating to
  the currently active version. This error has no FallbackController clause,
  so the API returns 500 instead of a clean error.
  """
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Flows

  @tag :known_bug
  test "migrate_flow_version to same active version returns :same_version error" do
    flow = insert(:flow)
    insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())
    {:ok, flow} = Flows.activate_flow(flow)

    # Migrate to version 1 which is already active
    result = Flows.migrate_flow_version(flow, 1)

    # This should return a clean error, not crash
    assert {:error, :same_version} = result
  end
end
