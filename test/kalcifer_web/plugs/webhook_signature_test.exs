defmodule KalciferWeb.Plugs.WebhookSignatureTest do
  use KalciferWeb.ConnCase, async: false

  @sendgrid_path "/api/v1/webhooks/sendgrid"
  @twilio_path "/api/v1/webhooks/twilio"

  describe "sendgrid signature verification" do
    setup %{conn: conn} do
      p256_oid = {1, 2, 840, 10_045, 3, 1, 7}
      private_key = :public_key.generate_key({:namedCurve, p256_oid})
      {:ECPrivateKey, _vsn, _priv, {:namedCurve, _oid}, public_point, _} = private_key
      public_key = {{:ECPoint, public_point}, {:namedCurve, p256_oid}}

      pem_entry = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)
      {:SubjectPublicKeyInfo, der, :not_encrypted} = pem_entry

      previous = Application.get_env(:kalcifer, :sendgrid, [])

      Application.put_env(:kalcifer, :sendgrid, webhook_verification_key: Base.encode64(der))

      on_exit(fn -> Application.put_env(:kalcifer, :sendgrid, previous) end)

      conn = put_req_header(conn, "content-type", "application/json")
      {:ok, conn: conn, private_key: private_key}
    end

    test "accepts a correctly signed payload", %{conn: conn, private_key: private_key} do
      raw_body = Jason.encode!(%{"event" => []})
      timestamp = "1700000000"

      signature =
        :public_key.sign(timestamp <> raw_body, :sha256, private_key) |> Base.encode64()

      conn =
        conn
        |> put_req_header("x-twilio-email-event-webhook-signature", signature)
        |> put_req_header("x-twilio-email-event-webhook-timestamp", timestamp)
        |> post(@sendgrid_path, raw_body)

      assert json_response(conn, 200)["processed"] == 0
    end

    test "rejects a tampered payload", %{conn: conn, private_key: private_key} do
      timestamp = "1700000000"

      signature =
        :public_key.sign(timestamp <> Jason.encode!(%{"event" => []}), :sha256, private_key)
        |> Base.encode64()

      conn =
        conn
        |> put_req_header("x-twilio-email-event-webhook-signature", signature)
        |> put_req_header("x-twilio-email-event-webhook-timestamp", timestamp)
        |> post(@sendgrid_path, Jason.encode!(%{"event" => [%{"forged" => true}]}))

      assert json_response(conn, 401)["error"] == "invalid webhook signature"
    end

    test "rejects when signature headers are missing", %{conn: conn} do
      conn = post(conn, @sendgrid_path, Jason.encode!(%{"event" => []}))

      assert json_response(conn, 401)["error"] == "invalid webhook signature"
    end
  end

  describe "twilio signature verification" do
    setup %{conn: conn} do
      previous = Application.get_env(:kalcifer, :twilio, [])
      Application.put_env(:kalcifer, :twilio, auth_token: "twilio-secret")
      on_exit(fn -> Application.put_env(:kalcifer, :twilio, previous) end)

      conn = put_req_header(conn, "content-type", "application/x-www-form-urlencoded")
      {:ok, conn: conn}
    end

    test "accepts a correctly signed request", %{conn: conn} do
      params = %{"MessageSid" => "SM-1", "MessageStatus" => "delivered"}

      data =
        params
        |> Enum.sort()
        |> Enum.reduce("http://www.example.com" <> @twilio_path, fn {k, v}, acc ->
          acc <> k <> v
        end)

      signature = Base.encode64(:crypto.mac(:hmac, :sha, "twilio-secret", data))

      conn =
        conn
        |> put_req_header("x-twilio-signature", signature)
        |> post(@twilio_path, URI.encode_query(params))

      assert json_response(conn, 200)["ok"] == true
    end

    test "rejects an invalid signature", %{conn: conn} do
      params = %{"MessageSid" => "SM-1", "MessageStatus" => "delivered"}

      conn =
        conn
        |> put_req_header("x-twilio-signature", Base.encode64("forged"))
        |> post(@twilio_path, URI.encode_query(params))

      assert json_response(conn, 401)["error"] == "invalid webhook signature"
    end

    test "rejects when signature header is missing", %{conn: conn} do
      params = %{"MessageSid" => "SM-1", "MessageStatus" => "delivered"}

      conn = post(conn, @twilio_path, URI.encode_query(params))

      assert json_response(conn, 401)["error"] == "invalid webhook signature"
    end
  end

  describe "unconfigured secrets" do
    test "verification is skipped when no secrets are configured", %{conn: conn} do
      previous_sendgrid = Application.get_env(:kalcifer, :sendgrid, [])
      previous_twilio = Application.get_env(:kalcifer, :twilio, [])
      Application.put_env(:kalcifer, :sendgrid, [])
      Application.put_env(:kalcifer, :twilio, [])

      on_exit(fn ->
        Application.put_env(:kalcifer, :sendgrid, previous_sendgrid)
        Application.put_env(:kalcifer, :twilio, previous_twilio)
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(@sendgrid_path, Jason.encode!(%{"event" => []}))

      assert json_response(conn, 200)["processed"] == 0
    end
  end
end
