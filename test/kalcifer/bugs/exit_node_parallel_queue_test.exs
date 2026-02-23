defmodule Kalcifer.Bugs.ExitNodeParallelQueueTest do
  @moduledoc """
  N1: Exit node in parallel execution queue marks instance completed,
  but execute_nodes continues processing remaining nodes in the queue.

  When a non-branching node has multiple outgoing edges (e.g. entry → exit
  AND entry → email), next_nodes returns both targets. The exit node fires
  first and calls complete_instance, but the loop continues to execute_single_node
  on remaining queue items — recording execution steps after completion.
  """
  use Kalcifer.DataCase, async: false

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Flows.ExecutionStep
  alias Kalcifer.Repo

  import Ecto.Query
  import Kalcifer.Factory

  defp parallel_exit_graph do
    %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "signed_up"}},
        %{"id" => "exit_1", "type" => "exit", "config" => %{}},
        %{"id" => "email_1", "type" => "send_email", "config" => %{"template_id" => "welcome"}},
        %{"id" => "exit_2", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        # Entry fans out to both exit_1 and email_1
        %{"id" => "e1", "source" => "entry_1", "target" => "exit_1"},
        %{"id" => "e2", "source" => "entry_1", "target" => "email_1"},
        %{"id" => "e3", "source" => "email_1", "target" => "exit_2"}
      ]
    }
  end

  @tag :known_bug
  test "exit node should stop execution of remaining queued nodes" do
    flow = insert(:flow)

    args = %{
      instance_id: Ecto.UUID.generate(),
      flow_id: flow.id,
      version_number: 1,
      customer_id: "customer_1",
      tenant_id: flow.tenant.id,
      graph: parallel_exit_graph()
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Kalcifer.Engine.FlowSupervisor,
        {FlowServer, args}
      )

    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      2000 -> :ok
    end

    # Get all execution steps for this instance
    steps =
      ExecutionStep
      |> where(instance_id: ^args.instance_id)
      |> order_by(:inserted_at)
      |> Repo.all()

    executed_ids = Enum.map(steps, & &1.node_id)

    # BUG: email_1 should NOT have been executed after exit_1 completed the instance.
    # Currently, execute_nodes continues processing the queue even after completion.
    refute "email_1" in executed_ids,
           "BUG: email_1 executed after exit_1 already completed the instance — " <>
             "execute_nodes should stop after exit/completion"
  end
end
