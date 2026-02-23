defmodule Kalcifer.Bugs.WaitUntilMigrationTest do
  @moduledoc """
  C6: wait_until migration cancels old Oban job but schedules no replacement.
  The apply_wait_change function in FlowServer has no "wait_until" arm in its
  inner case statement. Also, NodeMapper emits :duration_changed for wait_until
  datetime changes (wrong atom — I13).
  """
  use ExUnit.Case, async: true

  alias Kalcifer.Versioning.NodeMapper

  defp node(id, type, config) do
    %{"id" => id, "type" => type, "position" => %{"x" => 0, "y" => 0}, "config" => config}
  end

  defp graph(nodes), do: %{"nodes" => nodes, "edges" => []}

  @tag :known_bug
  test "NodeMapper emits :datetime_changed (not :duration_changed) for wait_until config change" do
    old_graph =
      graph([node("w", "wait_until", %{"datetime" => "2026-03-01T00:00:00Z"})])

    new_graph =
      graph([node("w", "wait_until", %{"datetime" => "2026-06-01T00:00:00Z"})])

    node_map = NodeMapper.build_mapping(old_graph, new_graph)
    changes = NodeMapper.detect_wait_changes(node_map)

    # BUG: Currently emits [{"w", :duration_changed}] for wait_until.
    # Should emit [{"w", :datetime_changed}] or a wait_until-specific change type.
    assert [{"w", change_type}] = changes

    assert change_type != :duration_changed,
           "BUG: wait_until datetime change emits :duration_changed — wrong atom, causes missing arm in FlowServer.apply_wait_change"
  end

  @tag :known_bug
  test "FlowServer.apply_wait_change should handle wait_until duration_changed" do
    # This test verifies the conceptual bug: FlowServer's apply_wait_change
    # has case arms for "wait" and "wait_for_event" but NOT "wait_until".
    # When a wait_until node's datetime changes during migration:
    # 1. Old Oban job is cancelled (via cancel_pending_resume_job)
    # 2. Inner case matches neither "wait" nor "wait_for_event"
    # 3. No new job is scheduled
    # 4. Customer is stuck forever

    # We verify this by checking the source code pattern
    source = File.read!("lib/kalcifer/engine/flow_server.ex")

    has_wait_until_arm =
      String.contains?(source, "\"wait_until\"") and
        String.contains?(source, "schedule_at")

    # In apply_wait_change's inner case block, there should be a "wait_until" arm
    # that calls schedule_at. Currently there isn't.
    assert has_wait_until_arm,
           "BUG: FlowServer.apply_wait_change has no 'wait_until' arm — " <>
             "datetime changes cancel the old job but schedule no replacement"
  end
end
