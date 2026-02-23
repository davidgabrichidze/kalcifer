defmodule Kalcifer.Channels.Jobs.SendMessageJob do
  @moduledoc false

  use Oban.Worker, queue: :channel_delivery, max_attempts: 5

  alias Kalcifer.Channels
  alias Kalcifer.Channels.ProviderRegistry

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

    with {:ok, provider} <- lookup_provider(channel_atom),
         {:ok, delivery} <- fetch_delivery(delivery_id),
         {:ok, provider_message_id} <-
           provider.send_message(channel_atom, recipient, message, provider_opts) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Channels.update_delivery_status(delivery, "sent", %{
        provider_message_id: provider_message_id,
        sent_at: now
      })

      :ok
    else
      {:error, reason} ->
        if delivery = Channels.get_delivery(delivery_id) do
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          Channels.update_delivery_status(delivery, "failed", %{
            error: inspect(reason),
            failed_at: now
          })
        end

        {:error, reason}
    end
  end

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
