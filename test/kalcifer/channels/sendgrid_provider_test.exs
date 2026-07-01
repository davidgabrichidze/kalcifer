defmodule Kalcifer.Channels.Providers.SendgridProviderTest do
  use ExUnit.Case, async: false

  alias Kalcifer.Channels.Providers.SendgridProvider

  @recipient %{"email" => "customer@example.com"}

  setup do
    previous = Application.get_env(:kalcifer, :sendgrid, [])

    Application.put_env(:kalcifer, :sendgrid,
      api_key: "SG.test-key",
      from_email: "hello@kalcifer.dev",
      from_name: "Kalcifer Test",
      req_options: [plug: {Req.Test, SendgridStub}]
    )

    on_exit(fn -> Application.put_env(:kalcifer, :sendgrid, previous) end)
    :ok
  end

  test "sends plain email and returns provider message id" do
    Req.Test.stub(SendgridStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert conn.method == "POST"
      assert conn.request_path == "/v3/mail/send"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer SG.test-key"]

      assert payload["personalizations"] == [%{"to" => [%{"email" => "customer@example.com"}]}]
      assert payload["from"] == %{"email" => "hello@kalcifer.dev", "name" => "Kalcifer Test"}
      assert payload["subject"] == "Welcome!"
      assert payload["content"] == [%{"type" => "text/plain", "value" => "Hello there"}]

      conn
      |> Plug.Conn.put_resp_header("x-message-id", "sg-msg-123")
      |> Plug.Conn.send_resp(202, "")
    end)

    message = %{"subject" => "Welcome!", "body" => "Hello there"}

    assert {:ok, "sg-msg-123"} = SendgridProvider.send_message(:email, @recipient, message, %{})
  end

  test "uses template_id with dynamic data when present" do
    Req.Test.stub(SendgridStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["template_id"] == "d-abc123"
      refute Map.has_key?(payload, "content")

      assert [%{"dynamic_template_data" => %{"subject" => "Hi"}}] =
               payload["personalizations"]

      Plug.Conn.send_resp(conn, 202, "")
    end)

    message = %{"template_id" => "d-abc123", "subject" => "Hi"}

    assert {:ok, message_id} = SendgridProvider.send_message(:email, @recipient, message, %{})
    assert is_binary(message_id)
  end

  test "message from_name and reply_to override config defaults" do
    Req.Test.stub(SendgridStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["from"]["name"] == "Acme Support"
      assert payload["reply_to"] == %{"email" => "support@acme.com"}

      Plug.Conn.send_resp(conn, 202, "")
    end)

    message = %{
      "subject" => "S",
      "body" => "B",
      "from_name" => "Acme Support",
      "reply_to" => "support@acme.com"
    }

    assert {:ok, _} = SendgridProvider.send_message(:email, @recipient, message, %{})
  end

  test "returns error when api key is missing" do
    Application.put_env(:kalcifer, :sendgrid, [])

    assert {:error, :missing_api_key} =
             SendgridProvider.send_message(:email, @recipient, %{"body" => "x"}, %{})
  end

  test "returns error when recipient email is missing" do
    assert {:error, :missing_recipient_email} =
             SendgridProvider.send_message(:email, %{"email" => nil}, %{"body" => "x"}, %{})
  end

  test "returns http_error on non-2xx response" do
    Req.Test.stub(SendgridStub, fn conn ->
      Plug.Conn.send_resp(conn, 401, Jason.encode!(%{"errors" => [%{"message" => "bad key"}]}))
    end)

    assert {:error, {:http_error, 401, _body}} =
             SendgridProvider.send_message(:email, @recipient, %{"body" => "x"}, %{})
  end

  test "returns error on transport failure" do
    Req.Test.stub(SendgridStub, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             SendgridProvider.send_message(:email, @recipient, %{"body" => "x"}, %{})
  end
end
