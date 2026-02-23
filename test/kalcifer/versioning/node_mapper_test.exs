defmodule Kalcifer.Versioning.NodeMapperTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Versioning.NodeMapper

  defp graph(nodes), do: %{"nodes" => nodes, "edges" => []}

  defp node(id, type, config \\ %{}) do
    %{"id" => id, "type" => type, "position" => %{"x" => 0, "y" => 0}, "config" => config}
  end

  describe "build_mapping/2" do
    test "identical graphs produce all matched, no removed or added" do
      g = graph([node("a", "entry"), node("b", "exit")])
      result = NodeMapper.build_mapping(g, g)

      assert length(result.matched) == 2
      assert result.removed == []
      assert result.added == []
    end

    test "node added in new graph" do
      old = graph([node("a", "entry")])
      new = graph([node("a", "entry"), node("b", "exit")])
      result = NodeMapper.build_mapping(old, new)

      assert length(result.matched) == 1
      assert length(result.added) == 1
      assert hd(result.added)["id"] == "b"
      assert result.removed == []
    end

    test "node removed in new graph" do
      old = graph([node("a", "entry"), node("b", "wait_for_event")])
      new = graph([node("a", "entry")])
      result = NodeMapper.build_mapping(old, new)

      assert length(result.matched) == 1
      assert length(result.removed) == 1
      assert hd(result.removed)["id"] == "b"
      assert result.added == []
    end

    test "detects config change on matched node" do
      old = graph([node("w", "wait", %{"duration" => "1h"})])
      new = graph([node("w", "wait", %{"duration" => "2h"})])
      result = NodeMapper.build_mapping(old, new)

      assert length(result.matched) == 1
      matched = hd(result.matched)
      assert :config_changed in matched.changes
    end

    test "no changes for identical matched nodes" do
      old = graph([node("a", "send_email", %{"template" => "t1"})])
      new = graph([node("a", "send_email", %{"template" => "t1"})])
      result = NodeMapper.build_mapping(old, new)

      assert hd(result.matched).changes == []
    end
  end

  describe "check_migration_safety/2" do
    test "returns :ok when current nodes exist in new version" do
      node_map = %{
        matched: [%{id: "a"}, %{id: "b"}],
        removed: [],
        added: []
      }

      assert :ok == NodeMapper.check_migration_safety(["a", "b"], node_map)
    end

    test "returns {:unsafe, :on_removed_node, ids} when current node was removed" do
      node_map = %{
        matched: [%{id: "a"}],
        removed: [%{"id" => "b"}],
        added: []
      }

      assert {:unsafe, :on_removed_node, ["b"]} =
               NodeMapper.check_migration_safety(["b"], node_map)
    end

    test "returns :ok when current nodes are all in matched set" do
      node_map = %{
        matched: [%{id: "a"}],
        removed: [%{"id" => "c"}],
        added: []
      }

      assert :ok == NodeMapper.check_migration_safety(["a"], node_map)
    end
  end

  describe "detect_wait_changes/1" do
    test "detects event_type change on wait_for_event" do
      node_map = %{
        matched: [
          %{
            id: "w",
            v1_node:
              node("w", "wait_for_event", %{"event_type" => "email_opened", "timeout" => "3d"}),
            v2_node:
              node("w", "wait_for_event", %{"event_type" => "push_opened", "timeout" => "3d"}),
            changes: [:config_changed]
          }
        ],
        removed: [],
        added: []
      }

      changes = NodeMapper.detect_wait_changes(node_map)
      assert {"w", :event_type_changed} in changes
    end

    test "detects duration change on wait node" do
      node_map = %{
        matched: [
          %{
            id: "w",
            v1_node: node("w", "wait", %{"duration" => "1h"}),
            v2_node: node("w", "wait", %{"duration" => "2h"}),
            changes: [:config_changed]
          }
        ],
        removed: [],
        added: []
      }

      changes = NodeMapper.detect_wait_changes(node_map)
      assert [{"w", :duration_changed}] == changes
    end

    test "detects timeout change on wait_for_event" do
      node_map = %{
        matched: [
          %{
            id: "w",
            v1_node: node("w", "wait_for_event", %{"event_type" => "e", "timeout" => "3d"}),
            v2_node: node("w", "wait_for_event", %{"event_type" => "e", "timeout" => "7d"}),
            changes: [:config_changed]
          }
        ],
        removed: [],
        added: []
      }

      changes = NodeMapper.detect_wait_changes(node_map)
      assert [{"w", :timeout_changed}] == changes
    end

    test "returns empty list when no wait nodes changed" do
      node_map = %{
        matched: [
          %{
            id: "e",
            v1_node: node("e", "send_email", %{"template" => "t1"}),
            v2_node: node("e", "send_email", %{"template" => "t2"}),
            changes: [:config_changed]
          }
        ],
        removed: [],
        added: []
      }

      assert [] == NodeMapper.detect_wait_changes(node_map)
    end
  end
end
