defmodule KalciferWeb.FlowChannelTest do
  use KalciferWeb.ChannelCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Tenants
  alias KalciferWeb.UserSocket

  @raw_api_key "flow_channel_test_key"

  setup do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)
    flow = insert(:flow, tenant: tenant)

    {:ok, socket} = connect(UserSocket, %{"api_key" => @raw_api_key})
    {:ok, socket: socket, flow: flow, tenant: tenant}
  end

  test "joining a flow topic pushes presence state", %{socket: socket, flow: flow} do
    {:ok, _reply, _socket} =
      subscribe_and_join(socket, "flow:#{flow.id}", %{
        "operator_id" => "op-anna",
        "operator_name" => "Anna"
      })

    assert_push "presence_state", state
    assert %{"op-anna" => %{metas: [%{name: "Anna"} | _]}} = state
  end

  test "second operator appears in presence diff", %{socket: socket, flow: flow} do
    {:ok, _reply, _socket} =
      subscribe_and_join(socket, "flow:#{flow.id}", %{"operator_id" => "op-1"})

    assert_push "presence_state", _state
    # our own join also produces a diff — consume it first
    assert_push "presence_diff", %{joins: %{"op-1" => _}}

    {:ok, second} = connect(UserSocket, %{"api_key" => @raw_api_key})

    {:ok, _reply, _socket2} =
      subscribe_and_join(second, "flow:#{flow.id}", %{
        "operator_id" => "op-2",
        "operator_name" => "Beka"
      })

    assert_push "presence_diff", %{joins: joins}
    assert %{"op-2" => %{metas: [%{name: "Beka"} | _]}} = joins
  end

  test "join is rejected for another tenant's flow", %{socket: socket} do
    other_flow = insert(:flow)

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(socket, "flow:#{other_flow.id}", %{})
  end
end
