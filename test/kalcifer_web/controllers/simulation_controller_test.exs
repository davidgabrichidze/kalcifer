defmodule KalciferWeb.SimulationControllerTest do
  @moduledoc """
  Tests for the simulation endpoint. Since SSE chunked responses
  don't accumulate in ConnTest, we test the underlying logic:
  flow resolution and dry-run execution.
  """
  use Kalcifer.DataCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Engine.Persistence.{InstanceStore, StepStore}
  alias Kalcifer.Flows

  describe "simulation flow — dry run execution" do
    test "active flow dry-run completes and records steps" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, graph: valid_graph())
      {:ok, flow} = Flows.activate_flow(flow)
      flow = Flows.get_flow(flow.id)

      version = Kalcifer.Repo.get(Kalcifer.Flows.FlowVersion, flow.active_version_id)
      instance_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "instance:#{instance_id}")

      args = %{
        instance_id: instance_id,
        flow_id: flow.id,
        customer_id: "sim_customer",
        tenant_id: tenant.id,
        version_number: version.version_number,
        graph: version.graph,
        initial_context: %{},
        dry_run: true
      }

      {:ok, _pid} =
        DynamicSupervisor.start_child(
          Kalcifer.Engine.FlowSupervisor,
          {FlowServer, args}
        )

      # Wait for completion
      assert_receive %{type: "instance_completed"}, 5000

      # Verify instance is completed and marked dry_run
      instance = InstanceStore.get_instance(instance_id)
      assert instance.status == "completed"
      assert instance.dry_run == true

      # Verify steps were recorded
      steps = StepStore.list_steps(instance_id)
      assert length(steps) >= 2

      types = Enum.map(steps, & &1.node_type)
      assert "event_entry" in types
      assert "exit" in types
    end

    test "draft flow can be simulated using latest version" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant, status: "draft")
      version = insert(:flow_version, flow: flow, graph: valid_graph())

      instance_id = Ecto.UUID.generate()
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "instance:#{instance_id}")

      args = %{
        instance_id: instance_id,
        flow_id: flow.id,
        customer_id: "sim_customer",
        tenant_id: tenant.id,
        version_number: version.version_number,
        graph: version.graph,
        initial_context: %{},
        dry_run: true
      }

      {:ok, _pid} =
        DynamicSupervisor.start_child(
          Kalcifer.Engine.FlowSupervisor,
          {FlowServer, args}
        )

      assert_receive %{type: "instance_completed"}, 5000

      instance = InstanceStore.get_instance(instance_id)
      assert instance.status == "completed"
      assert instance.dry_run == true
    end

    test "dry-run broadcasts node_executed events" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, graph: valid_graph())
      {:ok, flow} = Flows.activate_flow(flow)
      flow = Flows.get_flow(flow.id)

      version = Kalcifer.Repo.get(Kalcifer.Flows.FlowVersion, flow.active_version_id)
      instance_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "instance:#{instance_id}")

      args = %{
        instance_id: instance_id,
        flow_id: flow.id,
        customer_id: "sim_customer",
        tenant_id: tenant.id,
        version_number: version.version_number,
        graph: version.graph,
        initial_context: %{},
        dry_run: true
      }

      {:ok, _pid} =
        DynamicSupervisor.start_child(
          Kalcifer.Engine.FlowSupervisor,
          {FlowServer, args}
        )

      # Should receive node_executed events
      assert_receive %{type: "node_executed", payload: %{node_type: "event_entry"}}, 5000
      assert_receive %{type: "node_executed", payload: %{node_type: "exit"}}, 5000
      assert_receive %{type: "instance_completed"}, 5000
    end
  end
end
