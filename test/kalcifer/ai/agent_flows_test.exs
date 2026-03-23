defmodule Kalcifer.AI.AgentFlowsTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.AI.AgentFlows

  setup do
    tenant = insert(:tenant)
    %{tenant: tenant}
  end

  describe "ensure_simple_flow/1" do
    test "creates a new agent flow for tenant", %{tenant: tenant} do
      assert {:ok, {flow, version}} = AgentFlows.ensure_simple_flow(tenant.id)
      assert flow.name == "__agent_simple__"
      assert flow.status == "active"
      assert flow.tenant_id == tenant.id
      assert version.status == "published"

      # Graph structure: entry → agent → exit
      graph = version.graph
      assert length(graph["nodes"]) == 3
      assert length(graph["edges"]) == 2

      types = Enum.map(graph["nodes"], & &1["type"]) |> Enum.sort()
      assert types == ["agent", "exit", "webhook_entry"]
    end

    test "returns existing flow on second call (idempotent)", %{tenant: tenant} do
      assert {:ok, {flow1, _}} = AgentFlows.ensure_simple_flow(tenant.id)
      assert {:ok, {flow2, _}} = AgentFlows.ensure_simple_flow(tenant.id)
      assert flow1.id == flow2.id
    end

    test "different tenants get different flows" do
      tenant1 = insert(:tenant)
      tenant2 = insert(:tenant)

      assert {:ok, {flow1, _}} = AgentFlows.ensure_simple_flow(tenant1.id)
      assert {:ok, {flow2, _}} = AgentFlows.ensure_simple_flow(tenant2.id)
      assert flow1.id != flow2.id
    end
  end

  describe "ensure_council_flow/1" do
    test "creates a council flow with 7 nodes", %{tenant: tenant} do
      assert {:ok, {flow, version}} = AgentFlows.ensure_council_flow(tenant.id)
      assert flow.name == "__agent_council__"
      assert flow.status == "active"

      graph = version.graph
      assert length(graph["nodes"]) == 7
      assert length(graph["edges"]) == 6

      types = Enum.map(graph["nodes"], & &1["type"]) |> Enum.sort()
      assert types == ["agent", "ai_think", "ai_think", "ai_think", "ai_think", "exit", "webhook_entry"]

      ids = Enum.map(graph["nodes"], & &1["id"]) |> Enum.sort()
      assert "dreamer" in ids
      assert "realist" in ids
      assert "skeptic" in ids
      assert "synthesizer" in ids
      assert "executor" in ids
    end

    test "is idempotent", %{tenant: tenant} do
      assert {:ok, {flow1, _}} = AgentFlows.ensure_council_flow(tenant.id)
      assert {:ok, {flow2, _}} = AgentFlows.ensure_council_flow(tenant.id)
      assert flow1.id == flow2.id
    end
  end

  describe "agent_flow?/1" do
    test "returns true for agent flow names" do
      assert AgentFlows.agent_flow?("__agent_simple__")
      assert AgentFlows.agent_flow?("__agent_council__")
    end

    test "returns false for regular flow names" do
      refute AgentFlows.agent_flow?("My Onboarding Flow")
      refute AgentFlows.agent_flow?("agent_flow")
      refute AgentFlows.agent_flow?(nil)
    end
  end
end
