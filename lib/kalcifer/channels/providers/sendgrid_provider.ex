defmodule Kalcifer.Channels.Providers.SendgridProvider do
  @moduledoc """
  Email provider backed by the SendGrid v3 Mail Send API.

  Configuration (`config :kalcifer, :sendgrid`):
    - `api_key` — SendGrid API key (required to send)
    - `from_email` — default sender address
    - `from_name` — default sender display name
    - `req_options` — extra Req options, used by tests to stub HTTP

  Per-send options (`provider_opts` on the node config) may override
  `api_key`, `from_email`, `from_name` and set `reply_to`/`content_type`.
  """

  @behaviour Kalcifer.Channels.Provider

  @base_url "https://api.sendgrid.com"
  @default_from_email "no-reply@kalcifer.dev"
  @default_from_name "Kalcifer"

  @impl true
  def send_message(_channel, recipient, message, opts) do
    config = Application.get_env(:kalcifer, :sendgrid, [])
    api_key = opts["api_key"] || config[:api_key]
    to_email = recipient["email"]

    cond do
      api_key in [nil, ""] -> {:error, :missing_api_key}
      to_email in [nil, ""] -> {:error, :missing_recipient_email}
      true -> deliver(api_key, to_email, message, opts, config)
    end
  end

  defp deliver(api_key, to_email, message, opts, config) do
    req =
      Req.new(
        [
          base_url: @base_url,
          auth: {:bearer, api_key},
          receive_timeout: 15_000
        ] ++ Keyword.get(config, :req_options, [])
      )

    payload = build_payload(to_email, message, opts, config)

    case Req.post(req, url: "/v3/mail/send", json: payload) do
      {:ok, %{status: status} = resp} when status in 200..299 ->
        {:ok, message_id(resp)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_payload(to_email, message, opts, config) do
    from = %{
      "email" => opts["from_email"] || config[:from_email] || @default_from_email,
      "name" =>
        message["from_name"] || opts["from_name"] || config[:from_name] || @default_from_name
    }

    %{"personalizations" => [personalization(to_email, message)], "from" => from}
    |> put_reply_to(message, opts)
    |> put_content(message, opts)
  end

  defp personalization(to_email, message) do
    base = %{"to" => [%{"email" => to_email}]}

    case message["template_id"] do
      template_id when is_binary(template_id) and template_id != "" ->
        Map.put(base, "dynamic_template_data", Map.drop(message, ["template_id"]))

      _ ->
        base
    end
  end

  defp put_reply_to(payload, message, opts) do
    case message["reply_to"] || opts["reply_to"] do
      reply_to when is_binary(reply_to) and reply_to != "" ->
        Map.put(payload, "reply_to", %{"email" => reply_to})

      _ ->
        payload
    end
  end

  defp put_content(payload, message, opts) do
    case message["template_id"] do
      template_id when is_binary(template_id) and template_id != "" ->
        Map.put(payload, "template_id", template_id)

      _ ->
        content_type = opts["content_type"] || "text/plain"

        payload
        |> Map.put("subject", message["subject"] || "")
        |> Map.put("content", [%{"type" => content_type, "value" => message["body"] || ""}])
    end
  end

  defp message_id(resp) do
    case Req.Response.get_header(resp, "x-message-id") do
      [id | _] -> id
      [] -> Ecto.UUID.generate()
    end
  end
end
