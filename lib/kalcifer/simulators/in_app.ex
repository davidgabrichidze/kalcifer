defmodule Kalcifer.Simulators.InApp do
  @moduledoc """
  In-app message simulator: the message is stored instantly, then
  "delivered" when the customer's next session starts, and usually seen
  shortly after. Messages expire unseen when the customer never returns.

  `provider_opts["simulate"]`: `"seen" | "deliver" | "expire"`.
  Default distribution: 15% never seen (expired); delivered messages
  are seen 85% of the time.
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
      "expire" ->
        [
          %{
            status: "failed",
            event: %{"type" => "expired", "reason" => "no_session"},
            after_ms: Simulators.latency_ms(2)
          }
        ]

      "seen" ->
        [
          %{
            status: "delivered",
            event: %{"type" => "session_start"},
            after_ms: Simulators.latency_ms(1)
          },
          %{event: %{"type" => "seen"}, after_ms: Simulators.latency_ms(1)}
        ]

      _deliver ->
        [
          %{
            status: "delivered",
            event: %{"type" => "session_start"},
            after_ms: Simulators.latency_ms(1)
          }
        ]
    end
  end

  defp random_scenario do
    case Simulators.weighted(expire: 15, deliver: 85) do
      :expire ->
        "expire"

      :deliver ->
        if Simulators.weighted(seen: 85, no: 15) == :seen, do: "seen", else: "deliver"
    end
  end
end
