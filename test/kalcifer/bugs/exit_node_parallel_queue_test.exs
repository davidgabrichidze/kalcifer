defmodule Kalcifer.Bugs.ExitNodeParallelQueueTest do
  @moduledoc """
  N1 regression: execute_nodes must stop after exit node completes the instance.
  When entry fans out to [exit, email], only exit should execute.
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

  test "exit node stops execution of remaining queued nodes" do
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

    steps =
      ExecutionStep
      |> where(instance_id: ^args.instance_id)
      |> order_by(:inserted_at)
      |> Repo.all()

    executed_ids = Enum.map(steps, & &1.node_id)

    # After exit_1 completes the instance, email_1 must NOT execute
    refute "email_1" in executed_ids
    assert "entry_1" in executed_ids
    assert "exit_1" in executed_ids
  end
end
