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
end
