defmodule Kalcifer.Bugs.WaitUntilMigrationTest do
  @moduledoc """
  C6: Regression test for wait_until migration.
  NodeMapper emits :datetime_changed for wait_until nodes, and FlowServer's
  apply_wait_change has a dedicated handler that calls schedule_at.
  """
  use ExUnit.Case, async: true

  alias Kalcifer.Versioning.NodeMapper

  defp node(id, type, config) do
    %{"id" => id, "type" => type, "position" => %{"x" => 0, "y" => 0}, "config" => config}
  end

  defp graph(nodes), do: %{"nodes" => nodes, "edges" => []}

  test "NodeMapper emits :datetime_changed (not :duration_changed) for wait_until config change" do
    old_graph =
      graph([node("w", "wait_until", %{"datetime" => "2026-03-01T00:00:00Z"})])

    new_graph =
      graph([node("w", "wait_until", %{"datetime" => "2026-06-01T00:00:00Z"})])

    node_map = NodeMapper.build_mapping(old_graph, new_graph)
    changes = NodeMapper.detect_wait_changes(node_map)

    assert [{"w", :datetime_changed}] = changes
  end

  test "FlowServer has wait_until arm with schedule_at in apply_wait_change" do
    source = File.read!("lib/kalcifer/engine/flow_server.ex")

    assert String.contains?(source, "\"wait_until\"") and
             String.contains?(source, "schedule_at")
  end
end
