defmodule Kalcifer.Channels.Jobs.SendMessageJob do
  @moduledoc false

  use Oban.Worker, queue: :channel_delivery, max_attempts: 5

  alias Kalcifer.Channels
  alias Kalcifer.Channels.ProviderRegistry
  alias Kalcifer.Engine.CircuitBreaker

  # Matches the CircuitBreaker default cooldown so a snoozed job retries
  # right around the time the circuit transitions to half-open.
  @circuit_snooze_seconds 30

  @impl true
  def perform(%Oban.Job{args: args} = job) do
    channel_atom = String.to_existing_atom(args["channel"])

    if CircuitBreaker.allow?(channel_atom) do
      deliver(channel_atom, args, final_attempt?(job))
    else
      {:snooze, @circuit_snooze_seconds}
    end
  end

  defp final_attempt?(%Oban.Job{attempt: attempt, max_attempts: max}), do: attempt >= max

  defp deliver(channel_atom, args, final?) do
    %{
      "delivery_id" => delivery_id,
      "recipient" => recipient,
      "message" => message,
      "provider_opts" => provider_opts
    } = args

    with {:ok, provider} <- lookup_provider(channel_atom),
         {:ok, delivery} <- fetch_delivery(delivery_id) do
      provider.send_message(channel_atom, recipient, message, provider_opts)
      |> handle_send_result(channel_atom, delivery, final?)
    else
      # Setup errors (no provider registered, delivery row missing) are
      # permanent — retrying won't help, so mark failed right away.
      {:error, reason} ->
        with delivery when not is_nil(delivery) <- Channels.get_delivery(delivery_id) do
          mark_failed(delivery, reason)
        end

        {:error, reason}
    end
  end

  defp handle_send_result({:ok, provider_message_id}, channel_atom, delivery, _final?) do
    CircuitBreaker.record_success(channel_atom)

    Channels.update_delivery_status(delivery, "sent", %{
      provider_message_id: provider_message_id,
      sent_at: now()
    })

    :ok
  end

  defp handle_send_result({:error, reason}, channel_atom, delivery, final?) do
    CircuitBreaker.record_failure(channel_atom)
    # Only mark the delivery failed on the last attempt, so a transient error
    # followed by a successful retry isn't left as a (now terminal) "failed"
    # that the retry-success can't overwrite.
    if final?, do: mark_failed(delivery, reason)
    {:error, reason}
  end

  defp mark_failed(delivery, reason) do
    Channels.update_delivery_status(delivery, "failed", %{
      error: inspect(reason),
      failed_at: now()
    })
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp lookup_provider(channel_atom) do
    case ProviderRegistry.lookup(channel_atom) do
      {:ok, provider} -> {:ok, provider}
      :error -> {:error, {:no_provider, channel_atom}}
    end
  end

  defp fetch_delivery(delivery_id) do
    case Channels.get_delivery(delivery_id) do
      nil -> {:error, :delivery_not_found}
      delivery -> {:ok, delivery}
    end
  end
end
