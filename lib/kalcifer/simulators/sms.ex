defmodule Kalcifer.Simulators.Sms do
  @moduledoc """
  SMS provider simulator: emulates Twilio-style delivery reports —
  most messages deliver, a few fail at the carrier.

  `provider_opts["simulate"]`: `"deliver" | "fail"`.
  Default distribution: 95% delivered, 5% failed.
  """

  @behaviour Kalcifer.Channels.Provider

  alias Kalcifer.Simulators

  @impl true
  def send_message(_channel, _recipient, _message, opts) do
    message_id = Simulators.message_id()

    opts
    |> plan()
    |> then(&Simulators.schedule_plan(message_id, &1))

    {:ok, message_id}
  end

  @doc "Builds the delivery-report plan. Pure given a forced scenario."
  def plan(opts \\ %{}) do
    scenario = opts["simulate"] || random_scenario()

    case scenario do
      "fail" ->
        [
          %{
            status: "failed",
            event: %{"type" => "carrier_reject", "code" => "30005"},
            after_ms: Simulators.latency_ms(1)
          }
        ]

      _deliver ->
        [%{status: "delivered", after_ms: Simulators.latency_ms(1)}]
    end
  end

  defp random_scenario do
    case Simulators.weighted(fail: 5, deliver: 95) do
      :fail -> "fail"
      :deliver -> "deliver"
    end
  end
end
