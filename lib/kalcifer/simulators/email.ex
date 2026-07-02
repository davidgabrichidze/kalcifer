defmodule Kalcifer.Simulators.Email do
  @moduledoc """
  Email provider simulator: accepts every send, then emulates SendGrid
  style callbacks — delivery or bounce, followed by opens and clicks.

  `provider_opts["simulate"]`: `"deliver" | "bounce" | "open" | "click"`.
  Default distribution: 10% bounce; delivered mail opens 45% of the
  time, and 30% of opens click.
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
      "bounce" ->
        [%{status: "bounced", after_ms: Simulators.latency_ms(1)}]

      "deliver" ->
        [%{status: "delivered", after_ms: Simulators.latency_ms(1)}]

      "open" ->
        [
          %{status: "delivered", after_ms: Simulators.latency_ms(1)},
          %{event: %{"type" => "open"}, after_ms: Simulators.latency_ms(2)}
        ]

      "click" ->
        [
          %{status: "delivered", after_ms: Simulators.latency_ms(1)},
          %{event: %{"type" => "open"}, after_ms: Simulators.latency_ms(2)},
          %{event: %{"type" => "click"}, after_ms: Simulators.latency_ms(3)}
        ]

      _other ->
        plan(%{"simulate" => "deliver"})
    end
  end

  defp random_scenario do
    case Simulators.weighted(bounce: 10, deliver: 90) do
      :bounce -> "bounce"
      :deliver -> random_engagement()
    end
  end

  defp random_engagement do
    case Simulators.weighted(open: 45, plain: 55) do
      :plain -> "deliver"
      :open -> if Simulators.weighted(click: 30, no: 70) == :click, do: "click", else: "open"
    end
  end
end
