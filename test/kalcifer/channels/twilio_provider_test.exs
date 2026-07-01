defmodule Kalcifer.Channels.Providers.TwilioProviderTest do
  use ExUnit.Case, async: false

  alias Kalcifer.Channels.Providers.TwilioProvider

  @recipient %{"phone" => "+995555123456"}

  setup do
    previous = Application.get_env(:kalcifer, :twilio, [])

    Application.put_env(:kalcifer, :twilio,
      account_sid: "AC-test",
      auth_token: "token-test",
      from_number: "+14155550100",
      whatsapp_from: "+14155550199",
      req_options: [plug: {Req.Test, TwilioStub}]
    )

    on_exit(fn -> Application.put_env(:kalcifer, :twilio, previous) end)
    :ok
  end

  test "sends SMS and returns message sid" do
    Req.Test.stub(TwilioStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)

      assert conn.method == "POST"
      assert conn.request_path == "/2010-04-01/Accounts/AC-test/Messages.json"

      assert ["Basic " <> encoded] = Plug.Conn.get_req_header(conn, "authorization")
      assert Base.decode64!(encoded) == "AC-test:token-test"

      assert params["To"] == "+995555123456"
      assert params["From"] == "+14155550100"
      assert params["Body"] == "Hello via SMS"

      Req.Test.json(conn, %{"sid" => "SM-abc", "status" => "queued"})
    end)

    message = %{"body" => "Hello via SMS"}

    assert {:ok, "SM-abc"} = TwilioProvider.send_message(:sms, @recipient, message, %{})
  end

  test "sends WhatsApp with whatsapp: address prefixes" do
    Req.Test.stub(TwilioStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)

      assert params["To"] == "whatsapp:+995555123456"
      assert params["From"] == "whatsapp:+14155550199"

      Req.Test.json(conn, %{"sid" => "WA-xyz"})
    end)

    message = %{"body" => "Hello via WhatsApp"}

    assert {:ok, "WA-xyz"} = TwilioProvider.send_message(:whatsapp, @recipient, message, %{})
  end

  test "message sender_id overrides configured from number" do
    Req.Test.stub(TwilioStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)

      assert params["From"] == "+15005550006"

      Req.Test.json(conn, %{"sid" => "SM-override"})
    end)

    message = %{"body" => "Hi", "sender_id" => "+15005550006"}

    assert {:ok, "SM-override"} = TwilioProvider.send_message(:sms, @recipient, message, %{})
  end

  test "returns error when credentials are missing" do
    Application.put_env(:kalcifer, :twilio, [])

    assert {:error, :missing_credentials} =
             TwilioProvider.send_message(:sms, @recipient, %{"body" => "x"}, %{})
  end

  test "returns error when recipient phone is missing" do
    assert {:error, :missing_recipient_phone} =
             TwilioProvider.send_message(:sms, %{"phone" => nil}, %{"body" => "x"}, %{})
  end

  test "returns error when from number is missing" do
    Application.put_env(:kalcifer, :twilio,
      account_sid: "AC-test",
      auth_token: "token-test",
      req_options: [plug: {Req.Test, TwilioStub}]
    )

    assert {:error, :missing_from_number} =
             TwilioProvider.send_message(:sms, @recipient, %{"body" => "x"}, %{})
  end

  test "returns http_error on non-2xx response" do
    Req.Test.stub(TwilioStub, fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{"code" => 21_211, "message" => "Invalid 'To' number"})
    end)

    assert {:error, {:http_error, 400, %{"code" => 21_211}}} =
             TwilioProvider.send_message(:sms, @recipient, %{"body" => "x"}, %{})
  end

  test "returns error on transport failure" do
    Req.Test.stub(TwilioStub, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, %Req.TransportError{reason: :timeout}} =
             TwilioProvider.send_message(:sms, @recipient, %{"body" => "x"}, %{})
  end
end
