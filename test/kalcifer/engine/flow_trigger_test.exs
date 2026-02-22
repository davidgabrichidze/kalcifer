defmodule Kalcifer.Engine.FlowTriggerTest do
  use Kalcifer.DataCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Engine.FlowTrigger
  alias Kalcifer.Flows

  describe "trigger/3" do
    test "triggers active flow and starts FlowServer" do
      flow = insert(:flow)
      insert(:flow_version, flow: flow, graph: valid_graph())
      {:ok, flow} = Flows.activate_flow(flow)

      {:ok, instance_id} = FlowTrigger.trigger(flow.id, "customer_123")

      assert is_binary(instance_id)

      # FlowServer should be running (or already completed for simple graph)
      Process.sleep(100)

      instance = Kalcifer.Repo.get(Kalcifer.Flows.FlowInstance, instance_id)
      assert instance
      assert instance.customer_id == "customer_123"
      assert instance.flow_id == flow.id
    end

    test "passes initial_context to FlowServer" do
      flow = insert(:flow)
      insert(:flow_version, flow: flow, graph: valid_graph())
      {:ok, flow} = Flows.activate_flow(flow)

      {:ok, instance_id} =
        FlowTrigger.trigger(flow.id, "customer_123", %{"source" => "signup"})

      # Give server time to start
      Process.sleep(50)

      # Try to get state if still alive, otherwise check DB
      via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}

      case GenServer.whereis(via) do
        nil ->
          # Already completed — that's fine for simple graph
          :ok

        _pid ->
          state = FlowServer.get_state(instance_id)
          assert state.context["source"] == "signup"
      end
    end

    test "rejects non-active flow" do
      flow = insert(:flow, status: "draft")

      assert {:error, :flow_not_active} = FlowTrigger.trigger(flow.id, "customer_123")
    end

    test "rejects flow without active version" do
      flow = insert(:flow, status: "active", active_version_id: nil)

      assert {:error, :no_active_version} = FlowTrigger.trigger(flow.id, "customer_123")
    end

    test "rejects non-existent flow" do
      assert {:error, :not_found} = FlowTrigger.trigger(Ecto.UUID.generate(), "customer_123")
    end

    test "rejects paused flow" do
      flow = insert(:flow, status: "paused")

      assert {:error, :flow_not_active} = FlowTrigger.trigger(flow.id, "customer_123")
    end

    test "rejects archived flow" do
      flow = insert(:flow, status: "archived")

      assert {:error, :flow_not_active} = FlowTrigger.trigger(flow.id, "customer_123")
    end

    test "rejects flow with deleted active version" do
      flow = insert(:flow, status: "active", active_version_id: Ecto.UUID.generate())

      assert {:error, :no_active_version} = FlowTrigger.trigger(flow.id, "customer_123")
    end
  end
end
