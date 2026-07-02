defmodule Kalcifer.Simulators do
  @moduledoc """
  Shared plumbing for channel provider simulators.

  Each simulator returns `{:ok, provider_message_id}` immediately (like
  a real provider API) and schedules a *plan* — a list of steps that
  later change the delivery status (delivered/bounced/failed) or append
  engagement events (open, click, read, reply, seen) — emulating the
  asynchronous callbacks real providers send via webhooks.

  Outcomes are random by default; `provider_opts["simulate"]` forces a
  deterministic scenario per channel (e.g. `"bounce"`, `"click"`).
  Latency comes from `config :kalcifer, :simulators`.
  """

  alias Kalcifer.Channels
  alias Kalcifer.Simulators.Engine

  @type step :: %{
          optional(:status) => String.t(),
          optional(:event) => map(),
          after_ms: non_neg_integer()
        }

  @lookup_retries 10
  @lookup_retry_ms 50

  @doc "Generates a simulator provider message id."
  def message_id, do: "sim_" <> Ecto.UUID.generate()

  @doc """
  Schedules a plan against the delivery's provider message id. Steps are
  chained — the next step is only scheduled after the previous one has
  applied — so callback order is guaranteed even at zero latency.
  `after_ms` is therefore relative to the previous step.
  """
  def schedule_plan(_provider_message_id, []), do: :ok

  def schedule_plan(provider_message_id, [step | rest]) do
    Engine.schedule(step.after_ms, fn -> run_step(provider_message_id, step, rest) end)
    :ok
  end

  # Applies one plan step: status transition and/or engagement event.
  # The delivery row is created and marked "sent" by SendMessageJob after
  # the provider returns, so lookup retries briefly to avoid the race.
  defp run_step(provider_message_id, step, rest, retries \\ @lookup_retries) do
    case Channels.get_delivery_by_provider_message_id(provider_message_id) do
      nil when retries > 0 ->
        Engine.schedule(@lookup_retry_ms, fn ->
          run_step(provider_message_id, step, rest, retries - 1)
        end)

        :ok

      nil ->
        :not_found

      delivery ->
        delivery = maybe_transition(delivery, step[:status])
        maybe_event(delivery, step[:event])
        schedule_plan(provider_message_id, rest)
    end
  end

  @doc "Latency for the Nth simulated callback, from config."
  def latency_ms(n \\ 1) do
    config = Application.get_env(:kalcifer, :simulators, [])
    base = Keyword.get(config, :base_latency_ms, 500)
    jitter = Keyword.get(config, :jitter_ms, 1_000)

    n * base + jitter_value(jitter)
  end

  @doc "Picks an outcome key from a keyword list of {key, percent} weights."
  def weighted(choices) do
    roll = :rand.uniform(100)

    {key, _} =
      Enum.reduce_while(choices, {nil, 0}, fn {key, weight}, {_last, acc} ->
        acc = acc + weight
        if roll <= acc, do: {:halt, {key, acc}}, else: {:cont, {key, acc}}
      end)

    key
  end

  defp jitter_value(0), do: 0
  defp jitter_value(jitter), do: :rand.uniform(jitter)

  defp maybe_transition(delivery, nil), do: delivery

  defp maybe_transition(delivery, status) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      case status do
        "delivered" -> %{delivered_at: now}
        "bounced" -> %{failed_at: now}
        "failed" -> %{failed_at: now}
        _ -> %{}
      end

    case Channels.update_delivery_status(delivery, status, attrs) do
      {:ok, updated} -> updated
      {:error, _changeset} -> delivery
    end
  end

  defp maybe_event(_delivery, nil), do: :ok

  defp maybe_event(delivery, event) do
    Channels.append_delivery_event(delivery, event)
  end
end
