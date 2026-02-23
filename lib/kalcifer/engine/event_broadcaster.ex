defmodule Kalcifer.Engine.EventBroadcaster do
  @moduledoc false

  @pubsub Kalcifer.PubSub

  def broadcast_instance_started(state) do
    broadcast(state, "instance_started", %{
      instance_id: state.instance_id,
      flow_id: state.flow_id,
      customer_id: state.customer_id,
      version_number: state.version_number
    })
  end

  def broadcast_instance_completed(state) do
    broadcast(state, "instance_completed", %{
      instance_id: state.instance_id,
      flow_id: state.flow_id,
      customer_id: state.customer_id
    })
  end

  def broadcast_instance_failed(state) do
    broadcast(state, "instance_failed", %{
      instance_id: state.instance_id,
      flow_id: state.flow_id,
      customer_id: state.customer_id
    })
  end

  def broadcast_node_executed(state, node, result) do
    broadcast(state, "node_executed", %{
      instance_id: state.instance_id,
      flow_id: state.flow_id,
      node_id: node["id"],
      node_type: node["type"],
      result: result
    })
  end

  def broadcast_node_waiting(state, node) do
    broadcast(state, "node_waiting", %{
      instance_id: state.instance_id,
      flow_id: state.flow_id,
      node_id: node["id"],
      node_type: node["type"]
    })
  end

  def broadcast_node_resumed(state, node_id) do
    broadcast(state, "node_resumed", %{
      instance_id: state.instance_id,
      flow_id: state.flow_id,
      node_id: node_id
    })
  end

  defp broadcast(state, event_type, payload) do
    message = %{type: event_type, payload: payload, timestamp: DateTime.utc_now()}

    Phoenix.PubSub.broadcast(@pubsub, "flow:#{state.flow_id}", message)
    Phoenix.PubSub.broadcast(@pubsub, "instance:#{state.instance_id}", message)
    Phoenix.PubSub.broadcast(@pubsub, "tenant:#{state.tenant_id}", message)
  end
end
