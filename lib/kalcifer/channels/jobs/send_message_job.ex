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
  def perform(%Oban.Job{
        args: %{
          "delivery_id" => delivery_id,
          "channel" => channel,
          "recipient" => recipient,
          "message" => message,
          "provider_opts" => provider_opts
        }
      }) do
    channel_atom = String.to_existing_atom(channel)

    if CircuitBreaker.allow?(channel_atom) do
      deliver(channel_atom, delivery_id, recipient, message, provider_opts)
    else
      {:snooze, @circuit_snooze_seconds}
    end
  end

  defp deliver(channel_atom, delivery_id, recipient, message, provider_opts) do
    with {:ok, provider} <- lookup_provider(channel_atom),
         {:ok, delivery} <- fetch_delivery(delivery_id) do
      case provider.send_message(channel_atom, recipient, message, provider_opts) do
        {:ok, provider_message_id} ->
          CircuitBreaker.record_success(channel_atom)

          Channels.update_delivery_status(delivery, "sent", %{
            provider_message_id: provider_message_id,
            sent_at: now()
          })

          :ok

        {:error, reason} ->
          CircuitBreaker.record_failure(channel_atom)
          mark_failed(delivery, reason)
          {:error, reason}
      end
    else
      {:error, reason} ->
        with delivery when not is_nil(delivery) <- Channels.get_delivery(delivery_id) do
          mark_failed(delivery, reason)
        end

        {:error, reason}
    end
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
