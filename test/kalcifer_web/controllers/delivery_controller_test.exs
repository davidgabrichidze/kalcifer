defmodule KalciferWeb.DeliveryControllerTest do
  use KalciferWeb.ConnCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Channels

  test "index exposes engagement events on deliveries", %{conn: conn} do
    tenant = insert(:tenant)
    instance = insert(:flow_instance, tenant: tenant)

    {:ok, delivery} =
      Channels.create_delivery(%{
        channel: "email",
        recipient: %{"email" => "events@example.com"},
        instance_id: instance.id,
        tenant_id: tenant.id
      })

    {:ok, delivery} = Channels.update_delivery_status(delivery, "delivered", %{})
    {:ok, _} = Channels.append_delivery_event(delivery, %{"type" => "open"})

    body =
      conn
      |> put_req_header("x-tenant-id", tenant.id)
      |> get("/api/v1/deliveries")
      |> json_response(200)

    assert [%{"events" => [%{"type" => "open", "at" => _at}]}] =
             Enum.filter(body["data"], &(&1["id"] == delivery.id))
  end
end
