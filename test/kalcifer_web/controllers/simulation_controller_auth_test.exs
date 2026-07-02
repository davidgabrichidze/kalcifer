defmodule KalciferWeb.SimulationControllerAuthTest do
  @moduledoc """
  The simulate endpoint is served from the unauthenticated dev scope, so its
  flow lookup must be scoped to the resolved tenant — otherwise any caller can
  run (and read the graph + node output of) another tenant's flow. SSE chunked
  responses don't accumulate in ConnTest, so we exercise the resolver directly.
  """
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Flows
  alias KalciferWeb.SimulationController

  defp active_flow(tenant) do
    flow = insert(:flow, tenant: tenant)
    insert(:flow_version, flow: flow, graph: valid_graph())
    {:ok, flow} = Flows.activate_flow(flow)
    flow
  end

  test "resolves the caller's own flow to a runnable version" do
    owner = insert(:tenant)
    flow = active_flow(owner)

    assert {:ok, resolved, version} =
             SimulationController.resolve_flow_and_version(flow.id, owner)

    assert resolved.id == flow.id
    assert version.version_number == 1
  end

  test "rejects a flow owned by another tenant as not-found" do
    owner = insert(:tenant)
    flow = active_flow(owner)
    attacker = insert(:tenant)

    assert {:error, :not_found} =
             SimulationController.resolve_flow_and_version(flow.id, attacker)
  end
end
