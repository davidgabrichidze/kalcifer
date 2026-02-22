defmodule Kalcifer.Engine.RecoveryManagerTest do
  use Kalcifer.DataCase, async: false

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Engine.RecoveryManager
  alias Kalcifer.Flows.FlowInstance
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

  defp create_waiting_instance(opts \\ []) do
    flow = insert(:flow)

    insert(:flow_version,
      flow: flow,
      version_number: 1,
      graph: wait_graph(),
      status: "published"
    )

    scheduled_at =
      Keyword.get_lazy(opts, :scheduled_at, fn ->
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()
      end)

    insert(:flow_instance,
      flow: flow,
      tenant: flow.tenant,
      status: "waiting",
      version_number: 1,
      current_nodes: ["entry_1", "wait_1"],
      context: %{
        "_waiting_node_id" => "wait_1",
        "_resume_scheduled_at" => scheduled_at,
        "accumulated" => %{"entry_1" => %{"event_type" => "signed_up"}}
      }
    )
  end

  describe "recover/0" do
    test "recovers waiting instance and completes flow after resume" do
      instance = create_waiting_instance()

      RecoveryManager.recover()

      # In inline Oban mode, the resume job fires immediately via cast.
      # Give the FlowServer time to process the cast and complete.
      via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance.id}}
      pid = GenServer.whereis(via)

      if pid && Process.alive?(pid) do
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
        after
          2000 -> :ok
        end
      end

      reloaded = Repo.get!(FlowInstance, instance.id)
      assert reloaded.status == "completed"
    end

    test "marks running instance as failed" do
      flow = insert(:flow)

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: flow.tenant,
          status: "running",
          version_number: 1,
          current_nodes: ["entry_1"]
        )

      RecoveryManager.recover()

      reloaded = Repo.get!(FlowInstance, instance.id)
      assert reloaded.status == "failed"
      assert reloaded.exit_reason == "server_crashed"
    end

    test "skips already completed instances" do
      flow = insert(:flow)

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: flow.tenant,
          status: "completed",
          version_number: 1,
          current_nodes: []
        )

      RecoveryManager.recover()

      reloaded = Repo.get!(FlowInstance, instance.id)
      assert reloaded.status == "completed"

      via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance.id}}
      refute GenServer.whereis(via)
    end

    test "marks waiting instance as crashed when graph is missing" do
      flow = insert(:flow)
      # No flow_version created — graph cannot be loaded

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: flow.tenant,
          status: "waiting",
          version_number: 1,
          current_nodes: ["wait_1"],
          context: %{
            "_waiting_node_id" => "wait_1",
            "_resume_scheduled_at" => nil
          }
        )

      RecoveryManager.recover()

      reloaded = Repo.get!(FlowInstance, instance.id)
      assert reloaded.status == "failed"
      assert reloaded.exit_reason == "server_crashed"
    end
  end

  describe "FlowServer recovery init" do
    test "starts FlowServer in waiting state with recovered state" do
      flow = insert(:flow)

      insert(:flow_version,
        flow: flow,
        version_number: 1,
        graph: wait_graph(),
        status: "published"
      )

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: flow.tenant,
          status: "waiting",
          version_number: 1,
          current_nodes: ["entry_1", "wait_1"],
          context: %{
            "_waiting_node_id" => "wait_1",
            "accumulated" => %{"entry_1" => %{}}
          }
        )

      args = %{
        recovery: true,
        instance_id: instance.id,
        flow_id: flow.id,
        customer_id: instance.customer_id,
        tenant_id: flow.tenant_id,
        version_number: 1,
        graph: wait_graph(),
        current_nodes: ["entry_1", "wait_1"],
        context: instance.context,
        waiting_node_id: "wait_1"
      }

      {:ok, pid} =
        DynamicSupervisor.start_child(
          Kalcifer.Engine.FlowSupervisor,
          {FlowServer, args}
        )

      state = GenServer.call(pid, :get_state)
      assert state.status == :waiting
      assert state.waiting_node_id == "wait_1"
      assert state.current_nodes == ["entry_1", "wait_1"]
      assert state.context["accumulated"] == %{"entry_1" => %{}}

      GenServer.stop(pid, :normal)
    end
  end
end
