defmodule Kalcifer.Flows.FlowGraphTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Flows.FlowGraph

  describe "validate/1" do
    test "accepts a valid minimal graph (entry → exit)" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "exit_1"}
        ]
      }

      assert :ok = FlowGraph.validate(graph)
    end

    test "accepts a graph with branching wait_for_event" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{
            "id" => "wait_1",
            "type" => "wait_for_event",
            "config" => %{"event_type" => "email_opened", "timeout" => "3d"}
          },
          %{"id" => "email_1", "type" => "send_email", "config" => %{}},
          %{"id" => "email_2", "type" => "send_email", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
          %{
            "id" => "e2",
            "source" => "wait_1",
            "target" => "email_1",
            "branch" => "event_received"
          },
          %{"id" => "e3", "source" => "wait_1", "target" => "email_2", "branch" => "timed_out"},
          %{"id" => "e4", "source" => "email_1", "target" => "exit_1"},
          %{"id" => "e5", "source" => "email_2", "target" => "exit_1"}
        ]
      }

      assert :ok = FlowGraph.validate(graph)
    end

    test "accepts a graph with condition node" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "cond_1", "type" => "condition", "config" => %{}},
          %{"id" => "email_1", "type" => "send_email", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "cond_1"},
          %{"id" => "e2", "source" => "cond_1", "target" => "email_1", "branch" => "true"},
          %{"id" => "e3", "source" => "cond_1", "target" => "exit_1", "branch" => "false"}
        ]
      }

      assert :ok = FlowGraph.validate(graph)
    end

    test "accepts a graph with ab_split node" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{
            "id" => "split_1",
            "type" => "ab_split",
            "config" => %{
              "variants" => [%{"key" => "a", "weight" => 50}, %{"key" => "b", "weight" => 50}]
            }
          },
          %{"id" => "email_a", "type" => "send_email", "config" => %{}},
          %{"id" => "email_b", "type" => "send_email", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "split_1"},
          %{"id" => "e2", "source" => "split_1", "target" => "email_a", "branch" => "a"},
          %{"id" => "e3", "source" => "split_1", "target" => "email_b", "branch" => "b"},
          %{"id" => "e4", "source" => "email_a", "target" => "exit_1"},
          %{"id" => "e5", "source" => "email_b", "target" => "exit_1"}
        ]
      }

      assert :ok = FlowGraph.validate(graph)
    end
  end

  describe "validate/1 — no entry" do
    test "rejects graph without entry node" do
      graph = %{
        "nodes" => [
          %{"id" => "email_1", "type" => "send_email", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "email_1", "target" => "exit_1"}
        ]
      }

      assert {:error, errors} = FlowGraph.validate(graph)
      assert "graph must have at least one entry node" in errors
    end
  end

  describe "validate/1 — cycles" do
    test "detects a simple cycle" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "node_a", "type" => "send_email", "config" => %{}},
          %{"id" => "node_b", "type" => "send_email", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "node_a"},
          %{"id" => "e2", "source" => "node_a", "target" => "node_b"},
          %{"id" => "e3", "source" => "node_b", "target" => "node_a"}
        ]
      }

      assert {:error, errors} = FlowGraph.validate(graph)
      assert "graph contains a cycle" in errors
    end
  end

  describe "validate/1 — orphans" do
    test "detects orphan nodes not reachable from entry" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}},
          %{"id" => "orphan_1", "type" => "send_email", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "exit_1"}
        ]
      }

      assert {:error, errors} = FlowGraph.validate(graph)
      assert Enum.any?(errors, &String.contains?(&1, "orphan"))
    end
  end

  describe "validate/1 — invalid edges" do
    test "detects edges referencing non-existent nodes" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "nonexistent"}
        ]
      }

      assert {:error, errors} = FlowGraph.validate(graph)
      assert Enum.any?(errors, &String.contains?(&1, "unknown"))
    end
  end

  describe "validate/1 — incomplete branches" do
    test "detects missing branch edges on condition node" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "cond_1", "type" => "condition", "config" => %{}},
          %{"id" => "email_1", "type" => "send_email", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "cond_1"},
          # Only "true" branch, missing "false"
          %{"id" => "e2", "source" => "cond_1", "target" => "email_1", "branch" => "true"}
        ]
      }

      assert {:error, errors} = FlowGraph.validate(graph)
      assert Enum.any?(errors, &String.contains?(&1, "missing branch"))
    end

    test "detects missing branch edges on wait_for_event node" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{
            "id" => "wait_1",
            "type" => "wait_for_event",
            "config" => %{"event_type" => "email_opened", "timeout" => "3d"}
          },
          %{"id" => "email_1", "type" => "send_email", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
          # Only event_received branch, missing timed_out
          %{
            "id" => "e2",
            "source" => "wait_1",
            "target" => "email_1",
            "branch" => "event_received"
          }
        ]
      }

      assert {:error, errors} = FlowGraph.validate(graph)
      assert Enum.any?(errors, &String.contains?(&1, "missing branch"))
    end
  end

  describe "validate/1 — edge cases" do
    test "rejects non-map input" do
      assert {:error, ["graph must be a map"]} = FlowGraph.validate("not a map")
    end

    test "handles empty nodes list" do
      graph = %{"nodes" => [], "edges" => []}
      assert {:error, errors} = FlowGraph.validate(graph)
      assert "graph must have at least one entry node" in errors
    end
  end
end
