defmodule Kalcifer.Channels.Jobs.SendMessageJobCircuitTest do
  use Kalcifer.DataCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Channels
  alias Kalcifer.Channels.Jobs.SendMessageJob
  alias Kalcifer.Channels.ProviderRegistry
  alias Kalcifer.Engine.CircuitBreaker

  defmodule FailingProvider do
    @behaviour Kalcifer.Channels.Provider

    @impl true
    def send_message(_channel, _recipient, _message, _opts), do: {:error, :provider_down}
  end

  # Channel atoms used only by this test module so global registry/breaker
  # state cannot collide with other tests.
  @failing_channel :circuit_failing_channel
  @healthy_channel :circuit_healthy_channel

  setup do
    ProviderRegistry.register(@failing_channel, FailingProvider)
    ProviderRegistry.register(@healthy_channel, Kalcifer.Channels.Providers.LogProvider)

    CircuitBreaker.reset(@failing_channel)
    CircuitBreaker.reset(@healthy_channel)

    on_exit(fn ->
      CircuitBreaker.reset(@failing_channel)
      CircuitBreaker.reset(@healthy_channel)
    end)

    tenant = insert(:tenant)
    instance = insert(:flow_instance, tenant: tenant)
    {:ok, tenant: tenant, instance: instance}
  end

  defp build_job(channel, ctx) do
    {:ok, delivery} =
      Channels.create_delivery(%{
        channel: Atom.to_string(channel),
        recipient: %{"email" => "test@example.com"},
        message: %{"body" => "hi"},
        instance_id: ctx.instance.id,
        tenant_id: ctx.tenant.id
      })

    job = %Oban.Job{
      args: %{
        "delivery_id" => delivery.id,
        "channel" => Atom.to_string(channel),
        "recipient" => %{"email" => "test@example.com"},
        "message" => %{"body" => "hi"},
        "provider_opts" => %{}
      }
    }

    {delivery, job}
  end

  test "provider failures open the circuit after the threshold", ctx do
    for _ <- 1..5 do
      {_delivery, job} = build_job(@failing_channel, ctx)
      assert {:error, :provider_down} = SendMessageJob.perform(job)
    end

    assert CircuitBreaker.status(@failing_channel) == :open
  end

  test "open circuit snoozes the job without touching the delivery", ctx do
    for _ <- 1..5 do
      {_delivery, job} = build_job(@failing_channel, ctx)
      SendMessageJob.perform(job)
    end

    {delivery, job} = build_job(@failing_channel, ctx)

    assert {:snooze, 30} = SendMessageJob.perform(job)
    assert Channels.get_delivery(delivery.id).status == "pending"
  end

  test "successful send records success and keeps circuit closed", ctx do
    CircuitBreaker.record_failure(@healthy_channel)
    CircuitBreaker.record_failure(@healthy_channel)

    {delivery, job} = build_job(@healthy_channel, ctx)

    assert :ok = SendMessageJob.perform(job)
    assert Channels.get_delivery(delivery.id).status == "sent"
    assert CircuitBreaker.status(@healthy_channel) == :closed
  end
end
