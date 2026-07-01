defmodule Kalcifer.Channels.Providers.TwilioProvider do
  @moduledoc """
  SMS and WhatsApp provider backed by the Twilio Messages API.

  Configuration (`config :kalcifer, :twilio`):
    - `account_sid` — Twilio account SID (required to send)
    - `auth_token` — Twilio auth token (required to send)
    - `from_number` — default sender number for SMS
    - `whatsapp_from` — default sender number for WhatsApp
    - `req_options` — extra Req options, used by tests to stub HTTP

  Per-send options (`provider_opts` on the node config) may override
  `from_number`/`whatsapp_from`. The message `sender_id` field (from
  the SendSms node config) takes precedence over both.
  """

  @behaviour Kalcifer.Channels.Provider

  @base_url "https://api.twilio.com"

  @impl true
  def send_message(channel, recipient, message, opts) do
    config = Application.get_env(:kalcifer, :twilio, [])
    account_sid = opts["account_sid"] || config[:account_sid]
    auth_token = opts["auth_token"] || config[:auth_token]
    to_phone = recipient["phone"]
    from = from_number(channel, message, opts, config)

    cond do
      account_sid in [nil, ""] or auth_token in [nil, ""] -> {:error, :missing_credentials}
      to_phone in [nil, ""] -> {:error, :missing_recipient_phone}
      from in [nil, ""] -> {:error, :missing_from_number}
      true -> deliver(channel, account_sid, auth_token, to_phone, from, message, config)
    end
  end

  defp deliver(channel, account_sid, auth_token, to_phone, from, message, config) do
    req =
      Req.new(
        [
          base_url: @base_url,
          auth: {:basic, "#{account_sid}:#{auth_token}"},
          receive_timeout: 15_000
        ] ++ Keyword.get(config, :req_options, [])
      )

    form = [
      To: address(channel, to_phone),
      From: address(channel, from),
      Body: message["body"] || ""
    ]

    case Req.post(req, url: "/2010-04-01/Accounts/#{account_sid}/Messages.json", form: form) do
      {:ok, %{status: status} = resp} when status in 200..299 ->
        {:ok, message_sid(resp)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp from_number(:whatsapp, message, opts, config) do
    message["sender_id"] || opts["whatsapp_from"] || config[:whatsapp_from]
  end

  defp from_number(_channel, message, opts, config) do
    message["sender_id"] || opts["from_number"] || config[:from_number]
  end

  defp address(:whatsapp, number),
    do: "whatsapp:" <> String.replace_prefix(number, "whatsapp:", "")

  defp address(_channel, number), do: number

  defp message_sid(resp) do
    case resp.body do
      %{"sid" => sid} -> sid
      _ -> Ecto.UUID.generate()
    end
  end
end
