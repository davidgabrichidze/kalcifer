defmodule Kalcifer.Versioning.NodeMapperPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Kalcifer.Versioning.NodeMapper

  @node_types ~w(event_entry send_email send_sms wait wait_until wait_for_event branch exit)

  defp node_id_gen do
    gen all(
          prefix <- member_of(~w(n node step)),
          num <- integer(1..100)
        ) do
      "#{prefix}_#{num}"
    end
  end

  defp node_gen(id_gen \\ node_id_gen()) do
    gen all(
          id <- id_gen,
          type <- member_of(@node_types),
          config <- config_for_type(type)
        ) do
      %{
        "id" => id,
        "type" => type,
        "position" => %{"x" => 0, "y" => 0},
        "config" => config
      }
    end
  end

  defp config_for_type("wait"), do: constant(%{"duration" => "1h"})
  defp config_for_type("wait_until"), do: constant(%{"datetime" => "2026-01-01T00:00:00Z"})

  defp config_for_type("wait_for_event"),
    do: constant(%{"event_type" => "default_event", "timeout" => "3d"})

  defp config_for_type("event_entry"), do: constant(%{"event_type" => "signed_up"})
  defp config_for_type("send_email"), do: constant(%{"template_id" => "t1"})
  defp config_for_type("send_sms"), do: constant(%{"template_id" => "s1"})
  defp config_for_type("branch"), do: constant(%{"conditions" => []})
  defp config_for_type(_), do: constant(%{})

  defp graph_gen do
    gen all(nodes <- uniq_list_of(node_gen(), min_length: 1, max_length: 10, uniq_fun: & &1["id"])) do
      %{"nodes" => nodes, "edges" => []}
    end
  end

  describe "build_mapping/2 properties" do
    property "matched + removed = old nodes, matched + added = new nodes" do
      check all(
              old_graph <- graph_gen(),
              new_graph <- graph_gen()
            ) do
        result = NodeMapper.build_mapping(old_graph, new_graph)

        old_ids = MapSet.new(old_graph["nodes"], & &1["id"])
        new_ids = MapSet.new(new_graph["nodes"], & &1["id"])

        matched_ids = MapSet.new(result.matched, & &1.id)
        removed_ids = MapSet.new(result.removed, & &1["id"])
        added_ids = MapSet.new(result.added, & &1["id"])

        assert MapSet.union(matched_ids, removed_ids) == old_ids
        assert MapSet.union(matched_ids, added_ids) == new_ids
      end
    end

    property "matched, removed, and added are disjoint" do
      check all(
              old_graph <- graph_gen(),
              new_graph <- graph_gen()
            ) do
        result = NodeMapper.build_mapping(old_graph, new_graph)

        matched_ids = MapSet.new(result.matched, & &1.id)
        removed_ids = MapSet.new(result.removed, & &1["id"])
        added_ids = MapSet.new(result.added, & &1["id"])

        assert MapSet.disjoint?(matched_ids, removed_ids)
        assert MapSet.disjoint?(matched_ids, added_ids)
        assert MapSet.disjoint?(removed_ids, added_ids)
      end
    end

    property "mapping a graph against itself produces no removed or added" do
      check all(graph <- graph_gen()) do
        result = NodeMapper.build_mapping(graph, graph)

        assert result.removed == []
        assert result.added == []
        assert length(result.matched) == length(graph["nodes"])
      end
    end

    property "all matched nodes have valid changes list" do
      check all(
              old_graph <- graph_gen(),
              new_graph <- graph_gen()
            ) do
        result = NodeMapper.build_mapping(old_graph, new_graph)

        Enum.each(result.matched, fn m ->
          assert is_list(m.changes)
          assert Enum.all?(m.changes, &(&1 in [:type_changed, :config_changed]))
        end)
      end
    end
  end

  describe "check_migration_safety/2 properties" do
    property "safety is :ok when current_nodes subset of matched IDs" do
      check all(graph <- graph_gen()) do
        result = NodeMapper.build_mapping(graph, graph)
        all_ids = Enum.map(graph["nodes"], & &1["id"])

        subset = Enum.take(all_ids, max(1, div(length(all_ids), 2)))

        assert :ok == NodeMapper.check_migration_safety(subset, result)
      end
    end

    property "empty current_nodes is always safe" do
      check all(
              old_graph <- graph_gen(),
              new_graph <- graph_gen()
            ) do
        result = NodeMapper.build_mapping(old_graph, new_graph)
        assert :ok == NodeMapper.check_migration_safety([], result)
      end
    end
  end

  describe "detect_wait_changes/1 properties" do
    property "returns only tuples for wait-type nodes" do
      check all(
              old_graph <- graph_gen(),
              new_graph <- graph_gen()
            ) do
        result = NodeMapper.build_mapping(old_graph, new_graph)
        changes = NodeMapper.detect_wait_changes(result)

        wait_ids =
          old_graph["nodes"]
          |> Enum.filter(&(&1["type"] in ~w(wait wait_until wait_for_event)))
          |> MapSet.new(& &1["id"])

        Enum.each(changes, fn {id, change_type} ->
          assert MapSet.member?(wait_ids, id)

          assert change_type in [
                   :event_type_changed,
                   :duration_changed,
                   :timeout_changed
                 ]
        end)
      end
    end
  end
end
