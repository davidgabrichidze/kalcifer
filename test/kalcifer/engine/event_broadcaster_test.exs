defmodule Kalcifer.Engine.EventBroadcasterTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Engine.EventBroadcaster

  defp mock_state do
    %{
      instance_id: Ecto.UUID.generate(),
      flow_id: Ecto.UUID.generate(),
      customer_id: "customer_123",
      tenant_id: Ecto.UUID.generate(),
      version_number: 1
    }
  end

  test "broadcast_instance_started sends to flow topic" do
    state = mock_state()
    Phoenix.PubSub.subscribe(Kalcifer.PubSub, "flow:#{state.flow_id}")

    EventBroadcaster.broadcast_instance_started(state)

    assert_receive %{type: "instance_started", payload: payload}
    assert payload.instance_id == state.instance_id
    assert payload.flow_id == state.flow_id
  end

  test "broadcast_instance_completed sends to tenant topic" do
    state = mock_state()
    Phoenix.PubSub.subscribe(Kalcifer.PubSub, "tenant:#{state.tenant_id}")

    EventBroadcaster.broadcast_instance_completed(state)

    assert_receive %{type: "instance_completed", payload: payload}
    assert payload.instance_id == state.instance_id
  end

  test "broadcast_node_executed sends to instance topic" do
    state = mock_state()
    node = %{"id" => "entry_1", "type" => "event_entry"}
    Phoenix.PubSub.subscribe(Kalcifer.PubSub, "instance:#{state.instance_id}")

    EventBroadcaster.broadcast_node_executed(state, node, %{some: "result"})

    assert_receive %{type: "node_executed", payload: payload}
    assert payload.node_id == "entry_1"
    assert payload.node_type == "event_entry"
  end

  test "broadcast_node_waiting sends event" do
    state = mock_state()
    node = %{"id" => "wait_1", "type" => "wait"}
    Phoenix.PubSub.subscribe(Kalcifer.PubSub, "flow:#{state.flow_id}")

    EventBroadcaster.broadcast_node_waiting(state, node)

    assert_receive %{type: "node_waiting", payload: payload}
    assert payload.node_id == "wait_1"
  end

  test "broadcast_node_resumed sends event" do
    state = mock_state()
    Phoenix.PubSub.subscribe(Kalcifer.PubSub, "flow:#{state.flow_id}")

    EventBroadcaster.broadcast_node_resumed(state, "wait_1")

    assert_receive %{type: "node_resumed", payload: payload}
    assert payload.node_id == "wait_1"
  end

  test "broadcast_instance_failed sends event" do
    state = mock_state()
    Phoenix.PubSub.subscribe(Kalcifer.PubSub, "flow:#{state.flow_id}")

    EventBroadcaster.broadcast_instance_failed(state)

    assert_receive %{type: "instance_failed", payload: payload}
    assert payload.instance_id == state.instance_id
  end
end
