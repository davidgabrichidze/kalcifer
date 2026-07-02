defmodule Kalcifer.Simulators.EmailTest do
  use Kalcifer.DataCase, async: false

  import Kalcifer.Factory

  alias Ecto.Adapters.SQL.Sandbox
  alias Kalcifer.Channels
  alias Kalcifer.Repo
  alias Kalcifer.Simulators
  alias Kalcifer.Simulators.Email
  alias Kalcifer.Simulators.Engine

  setup do
    Sandbox.allow(Repo, self(), Process.whereis(Engine))
    :ok
  end

  defp create_sent_delivery(provider_message_id) do
    tenant = insert(:tenant)
    instance = insert(:flow_instance, tenant: tenant)

    {:ok, delivery} =
      Channels.create_delivery(%{
        channel: "email",
        recipient: %{"email" => "sim@example.com"},
        message: %{"subject" => "hi"},
        instance_id: instance.id,
        tenant_id: tenant.id
      })

    {:ok, delivery} =
      Channels.update_delivery_status(delivery, "sent", %{
        provider_message_id: provider_message_id
      })

    delivery
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

  describe "plan/1" do
    test "bounce scenario" do
      assert [%{status: "bounced"}] = Email.plan(%{"simulate" => "bounce"})
    end

    test "deliver scenario" do
      assert [%{status: "delivered"}] = Email.plan(%{"simulate" => "deliver"})
    end

    test "open scenario delivers then opens" do
      assert [%{status: "delivered"}, %{event: %{"type" => "open"}}] =
               Email.plan(%{"simulate" => "open"})
    end

    test "click scenario delivers, opens, clicks" do
      assert [
               %{status: "delivered"},
               %{event: %{"type" => "open"}},
               %{event: %{"type" => "click"}}
             ] = Email.plan(%{"simulate" => "click"})
    end

    test "random plans always start with a status step" do
      for _ <- 1..50 do
        assert [first | _] = Email.plan(%{})
        assert first[:status] in ["delivered", "bounced"]
      end
    end
  end

  describe "send_message/4 + engine" do
    test "click scenario transitions delivery and records events" do
      assert {:ok, message_id} =
               Email.send_message(:email, %{"email" => "x@y.z"}, %{}, %{
                 "simulate" => "click"
               })

      assert String.starts_with?(message_id, "sim_")
      delivery = create_sent_delivery(message_id)

      updated =
        wait_for(fn ->
          reloaded = Channels.get_delivery(delivery.id)
          if length(reloaded.events) == 2, do: reloaded
        end)

      assert updated, "simulator callbacks did not arrive in time"
      assert updated.status == "delivered"
      assert updated.delivered_at
      assert [%{"type" => "open", "at" => _}, %{"type" => "click", "at" => _}] = updated.events
    end

    test "bounce scenario marks delivery bounced" do
      assert {:ok, message_id} =
               Email.send_message(:email, %{"email" => "x@y.z"}, %{}, %{
                 "simulate" => "bounce"
               })

      delivery = create_sent_delivery(message_id)

      updated =
        wait_for(fn ->
          reloaded = Channels.get_delivery(delivery.id)
          if reloaded.status == "bounced", do: reloaded
        end)

      assert updated, "simulator callback did not arrive in time"
      assert updated.failed_at
    end
  end

  describe "weighted/1" do
    test "always returns one of the keys" do
      for _ <- 1..100 do
        assert Simulators.weighted(a: 10, b: 90) in [:a, :b]
      end
    end

    test "respects certainty" do
      for _ <- 1..20 do
        assert Simulators.weighted(only: 100) == :only
      end
    end
  end
end
