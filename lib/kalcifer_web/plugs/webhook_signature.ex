defmodule KalciferWeb.Plugs.WebhookSignature do
  @moduledoc """
  Verifies inbound delivery-status webhook signatures.

  - SendGrid: ECDSA P-256 / SHA-256 over `timestamp <> raw_body`
    (`X-Twilio-Email-Event-Webhook-Signature` / `-Timestamp` headers),
    verified against `config :kalcifer, :sendgrid` `:webhook_verification_key`
    (base64 DER public key, as shown in the SendGrid dashboard).
  - Twilio: HMAC-SHA1 over the request URL plus alphabetically sorted
    POST params (`X-Twilio-Signature` header), keyed by the auth token
    from `config :kalcifer, :twilio`.

  Verification is skipped when the corresponding secret is not
  configured, so dev/test setups keep working without credentials.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, provider: :sendgrid) do
    key = Application.get_env(:kalcifer, :sendgrid, [])[:webhook_verification_key]

    if key in [nil, ""], do: conn, else: verify_sendgrid(conn, key)
  end

  def call(conn, provider: :twilio) do
    token = Application.get_env(:kalcifer, :twilio, [])[:auth_token]

    if token in [nil, ""], do: conn, else: verify_twilio(conn, token)
  end

  defp verify_sendgrid(conn, key_base64) do
    with [signature_base64] <- get_req_header(conn, "x-twilio-email-event-webhook-signature"),
         [timestamp] <- get_req_header(conn, "x-twilio-email-event-webhook-timestamp"),
         raw_body when is_binary(raw_body) <- conn.assigns[:raw_body],
         {:ok, signature} <- Base.decode64(signature_base64),
         {:ok, public_key} <- decode_public_key(key_base64),
         true <- :public_key.verify(timestamp <> raw_body, :sha256, signature, public_key) do
      conn
    else
      _ -> reject(conn)
    end
  end

  defp verify_twilio(conn, auth_token) do
    case get_req_header(conn, "x-twilio-signature") do
      [signature] ->
        data =
          conn.body_params
          |> Enum.sort()
          |> Enum.reduce(request_url(conn), fn {key, value}, acc ->
            acc <> key <> to_string(value)
          end)

        expected = Base.encode64(:crypto.mac(:hmac, :sha, auth_token, data))

        if Plug.Crypto.secure_compare(expected, signature), do: conn, else: reject(conn)

      _ ->
        reject(conn)
    end
  end

  defp decode_public_key(key_base64) do
    pem_body =
      key_base64
      |> String.replace(~r/\s/, "")
      |> chunk_lines()

    pem = "-----BEGIN PUBLIC KEY-----\n" <> pem_body <> "-----END PUBLIC KEY-----\n"

    case :public_key.pem_decode(pem) do
      [entry] -> {:ok, :public_key.pem_entry_decode(entry)}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp chunk_lines(base64) do
    base64
    |> String.codepoints()
    |> Enum.chunk_every(64)
    |> Enum.map_join("", &(Enum.join(&1) <> "\n"))
  end

  defp reject(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: "invalid webhook signature"})
    |> halt()
  end
end
