defmodule Kalcifer.Bugs.ResumeFailedBranchTest do
  @moduledoc """
  T1: Verify behavior when resume triggers a failure path.

  When a wait node receives a wrong trigger (not :timer_expired), it returns
  {:failed, :unexpected_trigger}. The FlowServer should mark the instance failed
  and stop the process. A second resume should not arrive (process is dead).
  """
  use Kalcifer.DataCase, async: false

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Repo

  import Kalcifer.Factory

  defp wait_graph do
    %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "signed_up"}},
        %{"id" => "wait_1", "type" => "wait", "config" => %{"duration" => "3d"}},
        %{"id" => "exit_1", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
        %{"id" => "e2", "source" => "wait_1", "target" => "exit_1"}
      ]
    }
  end

  test "resume with wrong trigger fails instance and stops server" do
    flow = insert(:flow)

    args = %{
      instance_id: Ecto.UUID.generate(),
      flow_id: flow.id,
      version_number: 1,
      customer_id: "customer_1",
      tenant_id: flow.tenant.id,
      graph: wait_graph()
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Kalcifer.Engine.FlowSupervisor,
        {FlowServer, args}
      )

    # Wait for server to reach waiting state
    Process.sleep(200)
    assert Process.alive?(pid)

    state = GenServer.call(pid, :get_state)
    assert state.status == :waiting
    assert state.waiting_node_id == "wait_1"

    # Monitor the process to detect shutdown
    ref = Process.monitor(pid)

    # Send wrong trigger — wait node expects :timer_expired
    GenServer.cast(pid, {:resume, "wait_1", :wrong_trigger})

    # Server should stop after failing
    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
    after
      2000 -> flunk("server should have stopped after failed resume")
    end

    # Instance should be marked failed in DB
    instance = Repo.get(Kalcifer.Flows.FlowInstance, args.instance_id)
    assert instance.status == "failed"
    assert instance.exit_reason =~ "unexpected_trigger"
  end

  test "resume on non-matching node_id is silently ignored" do
    flow = insert(:flow)

    args = %{
      instance_id: Ecto.UUID.generate(),
      flow_id: flow.id,
      version_number: 1,
      customer_id: "customer_1",
      tenant_id: flow.tenant.id,
      graph: wait_graph()
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Kalcifer.Engine.FlowSupervisor,
        {FlowServer, args}
      )

    Process.sleep(200)
    assert Process.alive?(pid)

    # Send resume for wrong node_id — should hit catch-all, silently ignored
    GenServer.cast(pid, {:resume, "wrong_node", :timer_expired})

    # Server should still be alive and waiting
    Process.sleep(100)
    assert Process.alive?(pid)

    state = GenServer.call(pid, :get_state)
    assert state.status == :waiting
    assert state.waiting_node_id == "wait_1"

    # Clean up
    GenServer.stop(pid, :normal)
  end
end
