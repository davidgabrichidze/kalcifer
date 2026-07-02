defmodule Kalcifer.Channels.ChannelSenderTest do
  use Kalcifer.DataCase, async: true
  use Oban.Testing, repo: Kalcifer.Repo

  import Kalcifer.Factory

  alias Kalcifer.Channels
  alias Kalcifer.Channels.ChannelSender

  defp build_context(tenant \\ nil) do
    tenant = tenant || insert(:tenant)
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

  test "send with no tenant provider config persists a nil provider name" do
    ctx = build_context()

    assert {:completed, %{delivery_id: id}} = ChannelSender.send(:email, %{}, ctx)
    assert Channels.get_delivery(id).provider == nil
  end

  test "send honors the tenant's configured channel provider" do
    tenant =
      insert(:tenant,
        settings: %{
          "channel_providers" => %{
            "email" => %{
              "provider" => "sendgrid",
              "config" => %{"api_key" => "sk_tenant"}
            }
          }
        }
      )

    ctx = build_context(tenant)

    assert {:completed, %{delivery_id: id}} = ChannelSender.send(:email, %{}, ctx)

    # The chosen provider name is persisted on the delivery...
    assert Channels.get_delivery(id).provider == "sendgrid"

    # ...and carried into the enqueued job (name + merged opts) so the worker
    # dispatches through the tenant's provider, not the global default.
    assert_enqueued(
      worker: Kalcifer.Channels.Jobs.SendMessageJob,
      args: %{"provider" => "sendgrid", "provider_opts" => %{"api_key" => "sk_tenant"}}
    )
  end
end
