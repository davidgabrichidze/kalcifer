defmodule Kalcifer.Channels.ChannelSenderTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Channels.ChannelSender

  defp build_context do
    tenant = insert(:tenant)
    instance = insert(:flow_instance, tenant: tenant)

    %{
      "_tenant_id" => tenant.id,
      "_instance_id" => instance.id,
      "_customer_id" => instance.customer_id
    }
  end

  test "send creates delivery and enqueues job" do
    ctx = build_context()
    config = %{"template_id" => "welcome"}

    assert {:completed, %{delivery_id: id, channel: "email", status: "pending"}} =
             ChannelSender.send(:email, config, ctx)

    assert is_binary(id)
  end

  test "send with unknown provider returns failed" do
    ctx = build_context()
    config = %{}

    assert {:failed, {:no_provider, :unknown_channel}} =
             ChannelSender.send(:unknown_channel, config, ctx)
  end
end
