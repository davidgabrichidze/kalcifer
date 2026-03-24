defmodule Kalcifer.Flows.FlowGraphCyclesTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Flows.FlowGraph

  @cyclic_graph %{
    "nodes" => [
      %{"id" => "entry", "type" => "webhook_entry", "config" => %{}},
      %{"id" => "step_a", "type" => "ai_think", "config" => %{"prompt" => "think"}},
      %{"id" => "step_b", "type" => "ai_think", "config" => %{"prompt" => "think"}},
      %{"id" => "done", "type" => "exit", "config" => %{}}
    ],
    "edges" => [
      %{"id" => "e1", "source" => "entry", "target" => "step_a"},
      %{"id" => "e2", "source" => "step_a", "target" => "step_b"},
      %{"id" => "e3", "source" => "step_b", "target" => "step_a"},
      %{"id" => "e4", "source" => "step_b", "target" => "done"}
    ]
  }

  @acyclic_graph %{
    "nodes" => [
      %{"id" => "entry", "type" => "webhook_entry", "config" => %{}},
      %{"id" => "done", "type" => "exit", "config" => %{}}
    ],
    "edges" => [
      %{"id" => "e1", "source" => "entry", "target" => "done"}
    ]
  }

  describe "validate/2 with allow_cycles" do
    test "rejects cycles by default" do
      assert {:error, errors} = FlowGraph.validate(@cyclic_graph)
      assert Enum.any?(errors, &String.contains?(&1, "cycle"))
    end

    test "accepts cycles when allow_cycles: true" do
      assert :ok = FlowGraph.validate(@cyclic_graph, allow_cycles: true)
    end

    test "acyclic graph passes both modes" do
      assert :ok = FlowGraph.validate(@acyclic_graph)
      assert :ok = FlowGraph.validate(@acyclic_graph, allow_cycles: true)
    end
  end
end
