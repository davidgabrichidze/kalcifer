defmodule Kalcifer.Channels.Jobs.SendMessageJobTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Channels
  alias Kalcifer.Channels.Jobs.SendMessageJob

  test "perform sends message and updates delivery to sent" do
    tenant = insert(:tenant)
    instance = insert(:flow_instance, tenant: tenant)

    {:ok, delivery} =
      Channels.create_delivery(%{
        channel: "email",
        recipient: %{"email" => "test@example.com"},
        message: %{"template_id" => "welcome"},
        instance_id: instance.id,
        tenant_id: tenant.id
      })

    job = %Oban.Job{
      args: %{
        "delivery_id" => delivery.id,
        "channel" => "email",
        "recipient" => %{"email" => "test@example.com"},
        "message" => %{"template_id" => "welcome"},
        "provider_opts" => %{}
      }
    }

    assert :ok = SendMessageJob.perform(job)

    updated = Channels.get_delivery(delivery.id)
    assert updated.status == "sent"
    assert updated.provider_message_id != nil
  end

  test "perform marks delivery as failed when provider not found" do
    tenant = insert(:tenant)
    instance = insert(:flow_instance, tenant: tenant)

    {:ok, delivery} =
      Channels.create_delivery(%{
        channel: "unknown_channel",
        recipient: %{"email" => "test@example.com"},
        instance_id: instance.id,
        tenant_id: tenant.id
      })

    job = %Oban.Job{
      args: %{
        "delivery_id" => delivery.id,
        "channel" => "unknown_channel",
        "recipient" => %{"email" => "test@example.com"},
        "message" => %{},
        "provider_opts" => %{}
      }
    }

    assert {:error, {:no_provider, :unknown_channel}} = SendMessageJob.perform(job)

    updated = Channels.get_delivery(delivery.id)
    assert updated.status == "failed"
  end
end
