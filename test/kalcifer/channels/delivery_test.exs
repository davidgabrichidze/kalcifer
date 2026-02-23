defmodule Kalcifer.Channels.DeliveryTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Channels
  alias Kalcifer.Channels.Delivery

  test "create_delivery inserts a pending delivery record" do
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

    assert delivery.channel == "email"
    assert delivery.status == "pending"
    assert delivery.recipient["email"] == "test@example.com"
  end

  test "create_delivery requires instance_id and tenant_id" do
    {:error, changeset} =
      Channels.create_delivery(%{
        channel: "email",
        recipient: %{"email" => "test@example.com"}
      })

    assert %{instance_id: ["can't be blank"], tenant_id: ["can't be blank"]} =
             errors_on(changeset)
  end

  test "update_delivery_status transitions from pending to sent" do
    tenant = insert(:tenant)
    instance = insert(:flow_instance, tenant: tenant)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, delivery} =
      Channels.create_delivery(%{
        channel: "sms",
        recipient: %{"phone" => "+1234567890"},
        instance_id: instance.id,
        tenant_id: tenant.id
      })

    {:ok, updated} =
      Channels.update_delivery_status(delivery, "sent", %{
        provider_message_id: "msg_123",
        sent_at: now
      })

    assert updated.status == "sent"
    assert updated.provider_message_id == "msg_123"
  end

  test "status_changeset rejects invalid status" do
    delivery = %Delivery{id: Ecto.UUID.generate(), status: "pending"}
    changeset = Delivery.status_changeset(delivery, "invalid_status")
    refute changeset.valid?
  end
end
