defmodule Kalcifer.Simulators.Push do
  @moduledoc """
  Push notification simulator: emulates FCM-style outcomes — delivery,
  tap engagement, or failure for stale device tokens.

  `provider_opts["simulate"]`: `"deliver" | "tap" | "invalid_token"`.
  Default distribution: 8% invalid token; delivered pushes are tapped
  25% of the time.
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

  @doc "Builds the callback plan. Pure given a forced scenario."
  def plan(opts \\ %{}) do
    scenario = opts["simulate"] || random_scenario()

    case scenario do
      "invalid_token" ->
        [
          %{
            status: "failed",
            event: %{"type" => "invalid_token", "code" => "UNREGISTERED"},
            after_ms: Simulators.latency_ms(1)
          }
        ]

      "tap" ->
        [
          %{status: "delivered", after_ms: Simulators.latency_ms(1)},
          %{event: %{"type" => "tap"}, after_ms: Simulators.latency_ms(2)}
        ]

      _deliver ->
        [%{status: "delivered", after_ms: Simulators.latency_ms(1)}]
    end
  end

  defp random_scenario do
    case Simulators.weighted(invalid_token: 8, deliver: 92) do
      :invalid_token ->
        "invalid_token"

      :deliver ->
        if Simulators.weighted(tap: 25, no: 75) == :tap, do: "tap", else: "deliver"
    end
  end
end
