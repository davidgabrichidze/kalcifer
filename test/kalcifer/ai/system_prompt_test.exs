defmodule Kalcifer.AI.SystemPromptTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.AI.{Context, SystemPrompt}
  alias Kalcifer.Flows

  import Kalcifer.Factory

  test "returns the base prompt when there is no memory and no linked flow" do
    tenant = insert(:tenant)
    {:ok, conv} = Context.create_conversation(tenant.id)

    prompt = SystemPrompt.build(tenant.id, conv.id)

    assert prompt =~ "კალციფერი"
  end

  test "returns the base prompt for a nil conversation id" do
    tenant = insert(:tenant)

    assert SystemPrompt.build(tenant.id, nil) =~ "კალციფერი"
  end

  test "includes operator memory when present" do
    tenant = insert(:tenant)
    {:ok, _} = Context.remember(tenant.id, "brand_voice", "playful", "preference")
    {:ok, conv} = Context.create_conversation(tenant.id)

    prompt = SystemPrompt.build(tenant.id, conv.id)

    assert prompt =~ "brand_voice: playful"
  end

  test "includes the linked flow snapshot" do
    tenant = insert(:tenant)
    flow = insert(:flow, tenant: tenant, name: "Onboarding")
    insert(:flow_version, flow: flow, version_number: 1, status: "draft")
    {:ok, conv} = Context.create_conversation(tenant.id)
    {:ok, conv} = Context.link_entity(conv, "flow", flow.id)

    prompt = SystemPrompt.build(tenant.id, conv.id)

    assert prompt =~ "Onboarding"
    assert prompt =~ "entry_1 (event_entry)"
  end

  test "reflects manual graph edits on the next build (the sync loop)" do
    tenant = insert(:tenant)
    flow = insert(:flow, tenant: tenant)
    insert(:flow_version, flow: flow, version_number: 1, status: "draft")
    {:ok, conv} = Context.create_conversation(tenant.id)
    {:ok, conv} = Context.link_entity(conv, "flow", flow.id)

    # Simulate the operator saving from the visual editor
    # (same path as PUT /api/v1/flows/:flow_id/versions/:version_number).
    edited_graph = %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "signed_up"}},
        %{"id" => "manual_wait_1", "type" => "wait", "config" => %{"duration" => "1d"}},
        %{"id" => "exit_1", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"source" => "entry_1", "target" => "manual_wait_1"},
        %{"source" => "manual_wait_1", "target" => "exit_1"}
      ]
    }

    {:ok, _} = Flows.update_version(flow, 1, %{graph: edited_graph, changelog: "manual edit"})

    prompt = SystemPrompt.build(tenant.id, conv.id)

    assert prompt =~ "manual_wait_1"
  end
end
