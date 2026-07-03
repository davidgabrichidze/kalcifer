defmodule Kalcifer.AI.FlowSnapshotTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.AI.{Context, FlowSnapshot}

  import Kalcifer.Factory

  defp conversation_linked_to(flow) do
    {:ok, conv} = Context.create_conversation(flow.tenant_id)
    {:ok, conv} = Context.link_entity(conv, "flow", flow.id)
    conv
  end

  test "returns nil for nil conversation id" do
    tenant = insert(:tenant)
    assert FlowSnapshot.for_conversation(tenant.id, nil) == nil
  end

  test "returns nil when conversation has no linked flow" do
    tenant = insert(:tenant)
    {:ok, conv} = Context.create_conversation(tenant.id)

    assert FlowSnapshot.for_conversation(tenant.id, conv.id) == nil
  end

  test "returns nil when the linked flow has no versions" do
    flow = insert(:flow)
    conv = conversation_linked_to(flow)

    assert FlowSnapshot.for_conversation(flow.tenant_id, conv.id) == nil
  end

  test "renders flow name, version, nodes and edges for a linked draft flow" do
    flow = insert(:flow, name: "Onboarding")
    insert(:flow_version, flow: flow, version_number: 1, status: "draft")
    conv = conversation_linked_to(flow)

    snapshot = FlowSnapshot.for_conversation(flow.tenant_id, conv.id)

    assert snapshot =~ "Onboarding"
    assert snapshot =~ "Version: 1 (draft)"
    assert snapshot =~ "entry_1 (event_entry)"
    assert snapshot =~ "entry_1 → exit_1"
  end

  test "prefers the latest draft over an older published version" do
    flow = insert(:flow)
    insert(:flow_version, flow: flow, version_number: 1, status: "published")
    insert(:flow_version, flow: flow, version_number: 2, status: "draft")
    conv = conversation_linked_to(flow)

    assert FlowSnapshot.for_conversation(flow.tenant_id, conv.id) =~ "Version: 2 (draft)"
  end

  test "falls back to the latest version when no draft exists" do
    flow = insert(:flow)
    insert(:flow_version, flow: flow, version_number: 1, status: "published")
    insert(:flow_version, flow: flow, version_number: 2, status: "published")
    conv = conversation_linked_to(flow)

    assert FlowSnapshot.for_conversation(flow.tenant_id, conv.id) =~ "Version: 2 (published)"
  end

  test "truncates long config values" do
    long_value = String.duplicate("x", 500)

    graph = %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => long_value}},
        %{"id" => "exit_1", "type" => "exit", "config" => %{}}
      ],
      "edges" => [%{"source" => "entry_1", "target" => "exit_1"}]
    }

    flow = insert(:flow)
    insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: graph)
    conv = conversation_linked_to(flow)

    snapshot = FlowSnapshot.for_conversation(flow.tenant_id, conv.id)

    refute snapshot =~ long_value
    assert snapshot =~ "…"
  end

  test "omits configs above the node-count threshold and points at get_flow_graph" do
    nodes =
      for i <- 1..35 do
        %{"id" => "n#{i}", "type" => "wait", "config" => %{"duration" => "1d"}}
      end

    graph = %{"nodes" => nodes, "edges" => []}

    flow = insert(:flow)
    insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: graph)
    conv = conversation_linked_to(flow)

    snapshot = FlowSnapshot.for_conversation(flow.tenant_id, conv.id)

    assert snapshot =~ "n1 (wait)"
    refute snapshot =~ "duration"
    assert snapshot =~ "get_flow_graph"
  end

  test "returns nil when the conversation belongs to another tenant" do
    flow = insert(:flow)
    conv = conversation_linked_to(flow)
    other_tenant = insert(:tenant)

    assert FlowSnapshot.for_conversation(other_tenant.id, conv.id) == nil
  end

  test "returns nil when the linked flow belongs to a different tenant than the conversation" do
    flow = insert(:flow)
    insert(:flow_version, flow: flow, version_number: 1, status: "draft")
    other_tenant = insert(:tenant)
    {:ok, conv} = Context.create_conversation(other_tenant.id)
    {:ok, conv} = Context.link_entity(conv, "flow", flow.id)

    assert FlowSnapshot.for_conversation(other_tenant.id, conv.id) == nil
  end
end
