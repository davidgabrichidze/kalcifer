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

  describe "validate/1 — marketing branching nodes" do
    test "accepts a graph with check_segment true/false branches" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "seg_1", "type" => "check_segment", "config" => %{"segment_id" => "vip"}},
          %{"id" => "email_1", "type" => "send_email", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "seg_1"},
          %{"id" => "e2", "source" => "seg_1", "target" => "email_1", "branch" => "true"},
          %{"id" => "e3", "source" => "seg_1", "target" => "exit_1", "branch" => "false"}
        ]
      }

      assert :ok = FlowGraph.validate(graph)
    end

    test "accepts a graph with preference_gate true/false branches" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "pref_1", "type" => "preference_gate", "config" => %{"channel" => "email"}},
          %{"id" => "email_1", "type" => "send_email", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "pref_1"},
          %{"id" => "e2", "source" => "pref_1", "target" => "email_1", "branch" => "true"},
          %{"id" => "e3", "source" => "pref_1", "target" => "exit_1", "branch" => "false"}
        ]
      }

      assert :ok = FlowGraph.validate(graph)
    end

    test "detects missing branch edges on check_segment" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "seg_1", "type" => "check_segment", "config" => %{"segment_id" => "vip"}},
          %{"id" => "email_1", "type" => "send_email", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "seg_1"},
          %{"id" => "e2", "source" => "seg_1", "target" => "email_1", "branch" => "true"}
        ]
      }

      assert {:error, errors} = FlowGraph.validate(graph)
      assert Enum.any?(errors, &String.contains?(&1, "missing branch"))
    end
  end

  # --- Pre-flight analysis tests ---

  describe "validate_node_types/2" do
    test "returns :ok when all node types are registered" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => []
      }

      registry = stub_registry(%{"event_entry" => StubModule, "exit" => StubModule})
      assert :ok = FlowGraph.validate_node_types(graph, registry)
    end

    test "returns errors for unknown node types" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "n1", "type" => "nonexistent_type", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => []
      }

      registry = stub_registry(%{"event_entry" => StubModule, "exit" => StubModule})
      assert {:error, errors} = FlowGraph.validate_node_types(graph, registry)
      assert "unknown node type: nonexistent_type" in errors
    end

    test "deduplicates errors for same unknown type used multiple times" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "n1", "type" => "fake_node", "config" => %{}},
          %{"id" => "n2", "type" => "fake_node", "config" => %{}}
        ],
        "edges" => []
      }

      registry = stub_registry(%{"event_entry" => StubModule})
      assert {:error, errors} = FlowGraph.validate_node_types(graph, registry)
      assert errors == ["unknown node type: fake_node"]
    end
  end

  describe "analyze_config_completeness/2" do
    test "returns :ok when all node configs are valid" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => []
      }

      registry =
        stub_registry(%{
          "event_entry" => StubValidNode,
          "exit" => StubValidNode
        })

      assert :ok = FlowGraph.analyze_config_completeness(graph, registry)
    end

    test "returns errors when node validate/1 fails" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "n1", "type" => "bad_config_node", "config" => %{}}
        ],
        "edges" => []
      }

      registry =
        stub_registry(%{
          "event_entry" => StubValidNode,
          "bad_config_node" => StubInvalidNode
        })

      assert {:error, errors} = FlowGraph.analyze_config_completeness(graph, registry)
      assert Enum.any?(errors, &String.contains?(&1, "n1"))
      assert Enum.any?(errors, &String.contains?(&1, "missing required field"))
    end

    test "skips unknown node types gracefully" do
      graph = %{
        "nodes" => [
          %{"id" => "n1", "type" => "unknown_type", "config" => %{}}
        ],
        "edges" => []
      }

      registry = stub_registry(%{})
      assert :ok = FlowGraph.analyze_config_completeness(graph, registry)
    end
  end

  describe "analyze_context_deps/1" do
    test "extracts field names from condition nodes" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{
            "id" => "c1",
            "type" => "condition",
            "config" => %{"field" => "plan_type", "value" => "pro"}
          },
          %{
            "id" => "c2",
            "type" => "condition",
            "config" => %{"field" => "country", "value" => "US"}
          },
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => []
      }

      deps = FlowGraph.analyze_context_deps(graph)
      assert "plan_type" in deps
      assert "country" in deps
    end

    test "deduplicates field names" do
      graph = %{
        "nodes" => [
          %{
            "id" => "c1",
            "type" => "condition",
            "config" => %{"field" => "status", "value" => "a"}
          },
          %{
            "id" => "c2",
            "type" => "condition",
            "config" => %{"field" => "status", "value" => "b"}
          }
        ],
        "edges" => []
      }

      deps = FlowGraph.analyze_context_deps(graph)
      assert deps == ["status"]
    end

    test "ignores non-condition nodes" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "e1", "type" => "send_email", "config" => %{"template_id" => "x"}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => []
      }

      assert FlowGraph.analyze_context_deps(graph) == []
    end

    test "handles condition nodes with missing or blank field" do
      graph = %{
        "nodes" => [
          %{"id" => "c1", "type" => "condition", "config" => %{}},
          %{"id" => "c2", "type" => "condition", "config" => %{"field" => ""}}
        ],
        "edges" => []
      }

      assert FlowGraph.analyze_context_deps(graph) == []
    end
  end

  describe "preflight/2" do
    test "returns ok with empty warnings for valid graph" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "exit_1"}
        ]
      }

      registry = stub_registry(%{"event_entry" => StubValidNode, "exit" => StubValidNode})

      assert {:ok, %{warnings: [], context_deps: []}} = FlowGraph.preflight(graph, registry)
    end

    test "returns error for structural validation failures" do
      graph = %{"nodes" => [], "edges" => []}
      registry = stub_registry(%{})

      assert {:error, _} = FlowGraph.preflight(graph, registry)
    end

    test "returns error for unknown node types" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "n1", "type" => "fake_type", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "n1"},
          %{"id" => "e2", "source" => "n1", "target" => "exit_1"}
        ]
      }

      registry = stub_registry(%{"event_entry" => StubValidNode, "exit" => StubValidNode})

      assert {:error, errors} = FlowGraph.preflight(graph, registry)
      assert "unknown node type: fake_type" in errors
    end

    test "returns config warnings as advisory, not blocking" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "n1", "type" => "bad_node", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "n1"},
          %{"id" => "e2", "source" => "n1", "target" => "exit_1"}
        ]
      }

      registry =
        stub_registry(%{
          "event_entry" => StubValidNode,
          "exit" => StubValidNode,
          "bad_node" => StubInvalidNode
        })

      assert {:ok, %{warnings: warnings}} = FlowGraph.preflight(graph, registry)
      assert length(warnings) > 0
      assert Enum.any?(warnings, &String.contains?(&1, "missing required field"))
    end

    test "extracts context deps in preflight result" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{
            "id" => "c1",
            "type" => "condition",
            "config" => %{"field" => "age", "value" => "25"}
          },
          %{"id" => "exit_t", "type" => "exit", "config" => %{}},
          %{"id" => "exit_f", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "c1"},
          %{"id" => "e2", "source" => "c1", "target" => "exit_t", "branch" => "true"},
          %{"id" => "e3", "source" => "c1", "target" => "exit_f", "branch" => "false"}
        ]
      }

      registry =
        stub_registry(%{
          "event_entry" => StubValidNode,
          "exit" => StubValidNode,
          "condition" => StubValidNode
        })

      assert {:ok, %{context_deps: ["age"]}} = FlowGraph.preflight(graph, registry)
    end
  end

  # --- Stub registry and node modules for testing ---

  defmodule StubRegistry do
    def new(type_map) do
      {__MODULE__, type_map}
    end

    def lookup({__MODULE__, type_map}, type) do
      case Map.fetch(type_map, type) do
        {:ok, module} -> {:ok, module}
        :error -> :error
      end
    end
  end

  defmodule StubRegistryWrapper do
    # Wraps a map as a module that responds to lookup/1
    # We use process dictionary to store the map
    def put(type_map) do
      Process.put(:stub_registry_map, type_map)
    end

    def lookup(type) do
      type_map = Process.get(:stub_registry_map, %{})

      case Map.fetch(type_map, type) do
        {:ok, module} -> {:ok, module}
        :error -> :error
      end
    end
  end

  defmodule StubValidNode do
    def validate(_config), do: :ok
  end

  defmodule StubInvalidNode do
    def validate(_config), do: {:error, ["missing required field: template_id"]}
  end

  defp stub_registry(type_map) do
    StubRegistryWrapper.put(type_map)
    StubRegistryWrapper
  end

  # --- Original edge case tests ---

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

  describe "validate/1 — parallel entries" do
    test "accepts graph with multiple entry nodes converging to a single exit" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "entry_2", "type" => "segment_entry", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "exit_1"},
          %{"id" => "e2", "source" => "entry_2", "target" => "exit_1"}
        ]
      }

      assert :ok = FlowGraph.validate(graph)
    end

    test "accepts graph with three different entry types" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{"id" => "entry_2", "type" => "segment_entry", "config" => %{}},
          %{"id" => "entry_3", "type" => "webhook_entry", "config" => %{}},
          %{"id" => "email_1", "type" => "send_email", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "email_1"},
          %{"id" => "e2", "source" => "entry_2", "target" => "email_1"},
          %{"id" => "e3", "source" => "entry_3", "target" => "email_1"},
          %{"id" => "e4", "source" => "email_1", "target" => "exit_1"}
        ]
      }

      assert :ok = FlowGraph.validate(graph)
    end
  end

  describe "validate/1 — ab_split with 3+ variants" do
    test "accepts ab_split with 3 variants" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{
            "id" => "split_1",
            "type" => "ab_split",
            "config" => %{
              "variants" => [
                %{"key" => "a", "weight" => 34},
                %{"key" => "b", "weight" => 33},
                %{"key" => "c", "weight" => 33}
              ]
            }
          },
          %{"id" => "email_a", "type" => "send_email", "config" => %{}},
          %{"id" => "email_b", "type" => "send_email", "config" => %{}},
          %{"id" => "email_c", "type" => "send_email", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "split_1"},
          %{"id" => "e2", "source" => "split_1", "target" => "email_a", "branch" => "a"},
          %{"id" => "e3", "source" => "split_1", "target" => "email_b", "branch" => "b"},
          %{"id" => "e4", "source" => "split_1", "target" => "email_c", "branch" => "c"},
          %{"id" => "e5", "source" => "email_a", "target" => "exit_1"},
          %{"id" => "e6", "source" => "email_b", "target" => "exit_1"},
          %{"id" => "e7", "source" => "email_c", "target" => "exit_1"}
        ]
      }

      assert :ok = FlowGraph.validate(graph)
    end

    test "accepts ab_split with 4 variants" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{
            "id" => "split_1",
            "type" => "ab_split",
            "config" => %{
              "variants" => [
                %{"key" => "a", "weight" => 25},
                %{"key" => "b", "weight" => 25},
                %{"key" => "c", "weight" => 25},
                %{"key" => "d", "weight" => 25}
              ]
            }
          },
          %{"id" => "node_a", "type" => "send_email", "config" => %{}},
          %{"id" => "node_b", "type" => "send_sms", "config" => %{}},
          %{"id" => "node_c", "type" => "send_push", "config" => %{}},
          %{"id" => "node_d", "type" => "send_whatsapp", "config" => %{}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "split_1"},
          %{"id" => "e2", "source" => "split_1", "target" => "node_a", "branch" => "a"},
          %{"id" => "e3", "source" => "split_1", "target" => "node_b", "branch" => "b"},
          %{"id" => "e4", "source" => "split_1", "target" => "node_c", "branch" => "c"},
          %{"id" => "e5", "source" => "split_1", "target" => "node_d", "branch" => "d"},
          %{"id" => "e6", "source" => "node_a", "target" => "exit_1"},
          %{"id" => "e7", "source" => "node_b", "target" => "exit_1"},
          %{"id" => "e8", "source" => "node_c", "target" => "exit_1"},
          %{"id" => "e9", "source" => "node_d", "target" => "exit_1"}
        ]
      }

      assert :ok = FlowGraph.validate(graph)
    end

    test "detects missing branch on 3-variant ab_split" do
      graph = %{
        "nodes" => [
          %{"id" => "entry_1", "type" => "event_entry", "config" => %{}},
          %{
            "id" => "split_1",
            "type" => "ab_split",
            "config" => %{
              "variants" => [
                %{"key" => "a", "weight" => 34},
                %{"key" => "b", "weight" => 33},
                %{"key" => "c", "weight" => 33}
              ]
            }
          },
          %{"id" => "email_a", "type" => "send_email", "config" => %{}},
          %{"id" => "email_b", "type" => "send_email", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "split_1"},
          %{"id" => "e2", "source" => "split_1", "target" => "email_a", "branch" => "a"},
          %{"id" => "e3", "source" => "split_1", "target" => "email_b", "branch" => "b"}
          # Missing "c" branch
        ]
      }

      assert {:error, errors} = FlowGraph.validate(graph)
      assert Enum.any?(errors, &String.contains?(&1, "missing branch"))
    end
  end
end
