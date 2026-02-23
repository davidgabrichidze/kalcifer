defmodule Kalcifer.Bugs.FrequencyCapBranchingTest do
  @moduledoc """
  N5 regression: frequency_cap must be in FlowGraph's @branching_types.
  A graph with a frequency_cap node missing branch edges must fail validation.
  """
  use ExUnit.Case, async: true

  alias Kalcifer.Flows.FlowGraph

  test "graph with frequency_cap node missing branch edges fails validation" do
    graph = %{
      "nodes" => [
        %{
          "id" => "entry_1",
          "type" => "event_entry",
          "position" => %{"x" => 0, "y" => 0},
          "config" => %{"event_type" => "signed_up"}
        },
        %{
          "id" => "cap_1",
          "type" => "frequency_cap",
          "position" => %{"x" => 100, "y" => 0},
          "config" => %{"max_messages" => 5, "time_window" => "24h", "channel" => "email"}
        },
        %{
          "id" => "email_1",
          "type" => "send_email",
          "position" => %{"x" => 200, "y" => 0},
          "config" => %{"template_id" => "t1"}
        },
        %{
          "id" => "exit_1",
          "type" => "exit",
          "position" => %{"x" => 300, "y" => 0},
          "config" => %{}
        }
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "cap_1"},
        # Only "allowed" branch — missing "capped"
        %{"id" => "e2", "source" => "cap_1", "target" => "email_1", "branch" => "allowed"},
        %{"id" => "e3", "source" => "email_1", "target" => "exit_1"}
      ]
    }

    assert {:error, errors} = FlowGraph.validate(graph)
    assert Enum.any?(errors, &String.contains?(&1, "capped"))
  end

  test "graph with frequency_cap node with both branches passes validation" do
    graph = %{
      "nodes" => [
        %{
          "id" => "entry_1",
          "type" => "event_entry",
          "position" => %{"x" => 0, "y" => 0},
          "config" => %{"event_type" => "signed_up"}
        },
        %{
          "id" => "cap_1",
          "type" => "frequency_cap",
          "position" => %{"x" => 100, "y" => 0},
          "config" => %{"max_messages" => 5, "time_window" => "24h", "channel" => "email"}
        },
        %{
          "id" => "email_1",
          "type" => "send_email",
          "position" => %{"x" => 200, "y" => 0},
          "config" => %{"template_id" => "t1"}
        },
        %{
          "id" => "exit_1",
          "type" => "exit",
          "position" => %{"x" => 300, "y" => 0},
          "config" => %{}
        }
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "cap_1"},
        %{"id" => "e2", "source" => "cap_1", "target" => "email_1", "branch" => "allowed"},
        %{"id" => "e3", "source" => "cap_1", "target" => "exit_1", "branch" => "capped"},
        %{"id" => "e4", "source" => "email_1", "target" => "exit_1"}
      ]
    }

    assert :ok = FlowGraph.validate(graph)
  end
end
