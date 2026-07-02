defmodule Kalcifer.Simulators.SmsTest do
  use Kalcifer.DataCase, async: false

  import Kalcifer.Factory

  alias Ecto.Adapters.SQL.Sandbox
  alias Kalcifer.Channels
  alias Kalcifer.Repo
  alias Kalcifer.Simulators.Engine
  alias Kalcifer.Simulators.Sms

  setup do
    Sandbox.allow(Repo, self(), Process.whereis(Engine))
    :ok
  end

  describe "plan/1" do
    test "deliver scenario" do
      assert [%{status: "delivered"}] = Sms.plan(%{"simulate" => "deliver"})
    end

    test "fail scenario carries a carrier reject event" do
      assert [%{status: "failed", event: %{"type" => "carrier_reject"}}] =
               Sms.plan(%{"simulate" => "fail"})
    end

    test "random plans resolve to a terminal status" do
      for _ <- 1..50 do
        assert [%{status: status}] = Sms.plan(%{})
        assert status in ["delivered", "failed"]
      end
    end
  end

  test "failed send records event and status on the delivery" do
    assert {:ok, message_id} =
             Sms.send_message(:sms, %{"phone" => "+995555000001"}, %{}, %{
               "simulate" => "fail"
             })

    tenant = insert(:tenant)
    instance = insert(:flow_instance, tenant: tenant)

    {:ok, delivery} =
      Channels.create_delivery(%{
        channel: "sms",
        recipient: %{"phone" => "+995555000001"},
        instance_id: instance.id,
        tenant_id: tenant.id
      })

    {:ok, delivery} =
      Channels.update_delivery_status(delivery, "sent", %{provider_message_id: message_id})

    updated =
      wait_for(fn ->
        reloaded = Channels.get_delivery(delivery.id)
        if reloaded.status == "failed", do: reloaded
      end)

    assert updated, "simulator callback did not arrive in time"
    assert [%{"type" => "carrier_reject", "code" => "30005"}] = updated.events
    assert updated.failed_at
  end

  defp wait_for(fun, attempts \\ 50) do
    case fun.() do
      nil when attempts > 0 ->
        Process.sleep(20)
        wait_for(fun, attempts - 1)

      result ->
        result
    end
  end
end
