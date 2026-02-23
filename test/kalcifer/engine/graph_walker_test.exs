defmodule Kalcifer.Engine.GraphWalkerTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.GraphWalker

  import Kalcifer.Factory

  describe "entry_nodes/1" do
    test "returns entry nodes from a simple graph" do
      entries = GraphWalker.entry_nodes(valid_graph())
      assert length(entries) == 1
      assert hd(entries)["type"] == "event_entry"
    end

    test "returns entry nodes from a branching graph" do
      entries = GraphWalker.entry_nodes(branching_graph())
      assert length(entries) == 1
      assert hd(entries)["id"] == "entry_1"
    end

    test "returns empty list for graph with no entry nodes" do
      graph = %{
        "nodes" => [%{"id" => "x", "type" => "send_email", "config" => %{}}],
        "edges" => []
      }

      assert GraphWalker.entry_nodes(graph) == []
    end
  end

  describe "find_node/2" do
    test "returns node by id" do
      node = GraphWalker.find_node(valid_graph(), "entry_1")
      assert node["id"] == "entry_1"
      assert node["type"] == "event_entry"
    end

    test "returns nil for non-existent id" do
      assert GraphWalker.find_node(valid_graph(), "nonexistent") == nil
    end
  end

  describe "next_nodes/2" do
    test "returns all next nodes without branch filter" do
      next = GraphWalker.next_nodes(valid_graph(), "entry_1")
      assert length(next) == 1
      assert hd(next)["id"] == "exit_1"
    end

    test "returns multiple next nodes for branching node" do
      next = GraphWalker.next_nodes(branching_graph(), "wait_1")
      assert length(next) == 2
      ids = Enum.map(next, & &1["id"]) |> Enum.sort()
      assert ids == ["email_1", "email_2"]
    end
  end

  describe "next_nodes/3" do
    test "returns nodes on specific branch" do
      next = GraphWalker.next_nodes(branching_graph(), "wait_1", "event_received")
      assert length(next) == 1
      assert hd(next)["id"] == "email_1"
    end

    test "returns nodes on timed_out branch" do
      next = GraphWalker.next_nodes(branching_graph(), "wait_1", "timed_out")
      assert length(next) == 1
      assert hd(next)["id"] == "email_2"
    end

    test "returns empty list for non-existent branch" do
      assert GraphWalker.next_nodes(branching_graph(), "wait_1", "nonexistent") == []
    end
  end

  describe "entry_nodes/1 — multiple entry types" do
    test "returns all three entry types" do
      graph = %{
        "nodes" => [
          %{"id" => "e1", "type" => "event_entry", "config" => %{}},
          %{"id" => "e2", "type" => "segment_entry", "config" => %{}},
          %{"id" => "e3", "type" => "webhook_entry", "config" => %{}},
          %{"id" => "exit", "type" => "exit", "config" => %{}}
        ],
        "edges" => []
      }

      entries = GraphWalker.entry_nodes(graph)
      types = Enum.map(entries, & &1["type"]) |> Enum.sort()
      assert types == ["event_entry", "segment_entry", "webhook_entry"]
    end
  end

  describe "next_nodes/3 — condition branches" do
    test "follows true branch on condition node" do
      graph = condition_graph()
      next = GraphWalker.next_nodes(graph, "cond_1", "true")
      assert length(next) == 1
      assert hd(next)["id"] == "email_1"
    end

    test "follows false branch on condition node" do
      graph = condition_graph()
      next = GraphWalker.next_nodes(graph, "cond_1", "false")
      assert length(next) == 1
      assert hd(next)["id"] == "exit_1"
    end
  end

  describe "outgoing_edges/2" do
    test "returns outgoing edges for a node" do
      edges = GraphWalker.outgoing_edges(valid_graph(), "entry_1")
      assert length(edges) == 1
      assert hd(edges)["target"] == "exit_1"
    end

    test "returns multiple edges for branching node" do
      edges = GraphWalker.outgoing_edges(branching_graph(), "wait_1")
      assert length(edges) == 2
    end

    test "returns empty list for terminal node" do
      assert GraphWalker.outgoing_edges(valid_graph(), "exit_1") == []
    end
  end

  describe "edge cases" do
    test "find_node returns nil for node without id field" do
      graph = %{
        "nodes" => [%{"type" => "exit", "config" => %{}}],
        "edges" => []
      }

      assert GraphWalker.find_node(graph, "anything") == nil
    end

    test "next_nodes returns empty for orphan node" do
      graph = %{
        "nodes" => [
          %{"id" => "orphan", "type" => "send_email", "config" => %{}},
          %{"id" => "other", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "other", "target" => "orphan"}
        ]
      }

      assert GraphWalker.next_nodes(graph, "orphan") == []
    end

    test "entry_nodes returns empty when no entry types exist" do
      graph = %{
        "nodes" => [
          %{"id" => "a", "type" => "send_email", "config" => %{}},
          %{"id" => "b", "type" => "exit", "config" => %{}}
        ],
        "edges" => [%{"id" => "e1", "source" => "a", "target" => "b"}]
      }

      assert GraphWalker.entry_nodes(graph) == []
    end

    test "handles graph with missing nodes key" do
      graph = %{"edges" => [%{"id" => "e1", "source" => "a", "target" => "b"}]}

      assert GraphWalker.entry_nodes(graph) == []
      assert GraphWalker.find_node(graph, "a") == nil
      assert GraphWalker.next_nodes(graph, "a") == []
    end

    test "handles graph with missing edges key" do
      graph = %{
        "nodes" => [%{"id" => "a", "type" => "event_entry", "config" => %{}}]
      }

      assert GraphWalker.entry_nodes(graph) == [
               %{"id" => "a", "type" => "event_entry", "config" => %{}}
             ]

      assert GraphWalker.next_nodes(graph, "a") == []
      assert GraphWalker.outgoing_edges(graph, "a") == []
    end

    test "next_nodes with branch_key returns empty when no branch matches" do
      graph = %{
        "nodes" => [
          %{"id" => "a", "type" => "condition", "config" => %{}},
          %{"id" => "b", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "a", "target" => "b", "branch" => "true"}
        ]
      }

      assert GraphWalker.next_nodes(graph, "a", "false") == []
    end
  end

  defp condition_graph do
    %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
        %{"id" => "cond_1", "type" => "condition", "config" => %{}},
        %{"id" => "email_1", "type" => "send_email", "config" => %{}},
        %{"id" => "exit_1", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "cond_1"},
        %{"id" => "e2", "source" => "cond_1", "target" => "email_1", "branch" => "true"},
        %{"id" => "e3", "source" => "cond_1", "target" => "exit_1", "branch" => "false"},
        %{"id" => "e4", "source" => "email_1", "target" => "exit_1"}
      ]
    }
  end
end
