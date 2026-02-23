defmodule Kalcifer.Channels.Providers.WebhookProvider do
  @moduledoc false

  @behaviour Kalcifer.Channels.Provider

  @impl true
  def send_message(_channel, recipient, message, opts) do
    url = opts["url"] || recipient["webhook_url"]

    if url do
      payload = %{recipient: recipient, message: message, timestamp: DateTime.utc_now()}
      headers = build_headers(payload, opts)

      case Req.post(url, json: payload, headers: headers, receive_timeout: 15_000) do
        {:ok, %{status: status}} when status in 200..299 ->
          {:ok, Ecto.UUID.generate()}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :missing_webhook_url}
    end
  end

  defp build_headers(payload, opts) do
    case opts["signing_secret"] do
      nil ->
        [{"content-type", "application/json"}]

      secret ->
        body = Jason.encode!(payload)
        signature = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)

        [
          {"content-type", "application/json"},
          {"x-kalcifer-signature", signature}
        ]
    end
  end
end
