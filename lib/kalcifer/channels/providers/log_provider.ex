defmodule Kalcifer.Channels.Providers.LogProvider do
  @moduledoc false

  @behaviour Kalcifer.Channels.Provider

  require Logger

  @impl true
  def send_message(channel, recipient, message, _opts) do
    delivery_id = Ecto.UUID.generate()

    Logger.info(
      "log_provider.send_message channel=#{channel} recipient=#{inspect(recipient)} " <>
        "message_keys=#{inspect(Map.keys(message))} delivery_id=#{delivery_id}"
    )

    {:ok, delivery_id}
  end

  @impl true
  def delivery_status(delivery_id) do
    {:ok, "delivered_#{delivery_id}"}
  end
end
