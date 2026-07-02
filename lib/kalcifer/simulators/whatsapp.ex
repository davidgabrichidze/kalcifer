defmodule Kalcifer.Simulators.Whatsapp do
  @moduledoc """
  WhatsApp simulator: emulates Twilio WhatsApp callbacks — delivery,
  read receipts and inbound replies, or failure when the recipient has
  no WhatsApp account.

  `provider_opts["simulate"]`: `"deliver" | "read" | "reply" | "no_account"`.
  Default distribution: 5% no account; delivered messages are read 70%
  of the time, and 20% of reads get a reply.
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
      "no_account" ->
        [
          %{
            status: "failed",
            event: %{"type" => "no_whatsapp_account", "code" => "63003"},
            after_ms: Simulators.latency_ms(1)
          }
        ]

      "read" ->
        [
          %{status: "delivered", after_ms: Simulators.latency_ms(1)},
          %{event: %{"type" => "read"}, after_ms: Simulators.latency_ms(2)}
        ]

      "reply" ->
        [
          %{status: "delivered", after_ms: Simulators.latency_ms(1)},
          %{event: %{"type" => "read"}, after_ms: Simulators.latency_ms(2)},
          %{
            event: %{"type" => "reply", "body" => "👍 მადლობა!"},
            after_ms: Simulators.latency_ms(3)
          }
        ]

      _deliver ->
        [%{status: "delivered", after_ms: Simulators.latency_ms(1)}]
    end
  end

  defp random_scenario do
    case Simulators.weighted(no_account: 5, deliver: 95) do
      :no_account -> "no_account"
      :deliver -> random_engagement()
    end
  end

  defp random_engagement do
    case Simulators.weighted(read: 70, plain: 30) do
      :plain -> "deliver"
      :read -> if Simulators.weighted(reply: 20, no: 80) == :reply, do: "reply", else: "read"
    end
  end
end
