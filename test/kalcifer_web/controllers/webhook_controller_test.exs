defmodule KalciferWeb.WebhookControllerTest do
  use KalciferWeb.ConnCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Channels

  setup %{conn: conn} do
    conn = put_req_header(conn, "content-type", "application/json")
    {:ok, conn: conn}
  end

  describe "POST /api/v1/webhooks/sendgrid" do
    test "processes delivery status events", %{conn: conn} do
      tenant = insert(:tenant)
      instance = insert(:flow_instance, tenant: tenant)

      {:ok, delivery} =
        Channels.create_delivery(%{
          channel: "email",
          recipient: %{"email" => "test@example.com"},
          instance_id: instance.id,
          tenant_id: tenant.id
        })

      Channels.update_delivery_status(delivery, "sent", %{
        provider_message_id: "sg_msg_001"
      })

      events = [
        %{"sg_message_id" => "sg_msg_001", "event" => "delivered", "timestamp" => 1_234_567_890}
      ]

      conn_resp = post(conn, "/api/v1/webhooks/sendgrid", %{"event" => events})
      assert json_response(conn_resp, 200)["processed"] == 1

      updated = Channels.get_delivery(delivery.id)
      assert updated.status == "delivered"
    end

    test "returns 400 for missing event array", %{conn: conn} do
      conn_resp = post(conn, "/api/v1/webhooks/sendgrid", %{})
      assert json_response(conn_resp, 400)["error"] == "expected event array"
    end
  end

  describe "POST /api/v1/webhooks/twilio" do
    test "processes SMS delivery status", %{conn: conn} do
      tenant = insert(:tenant)
      instance = insert(:flow_instance, tenant: tenant)

      {:ok, delivery} =
        Channels.create_delivery(%{
          channel: "sms",
          recipient: %{"phone" => "+1234567890"},
          instance_id: instance.id,
          tenant_id: tenant.id
        })

      Channels.update_delivery_status(delivery, "sent", %{
        provider_message_id: "SM_twilio_001"
      })

      conn_resp =
        post(conn, "/api/v1/webhooks/twilio", %{
          "MessageSid" => "SM_twilio_001",
          "MessageStatus" => "delivered"
        })

      assert json_response(conn_resp, 200)["ok"] == true

      updated = Channels.get_delivery(delivery.id)
      assert updated.status == "delivered"
    end

    test "returns 400 for missing params", %{conn: conn} do
      conn_resp = post(conn, "/api/v1/webhooks/twilio", %{})
      assert json_response(conn_resp, 400)["error"] == "missing MessageSid or MessageStatus"
    end
  end
end
