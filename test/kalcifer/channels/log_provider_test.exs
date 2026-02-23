defmodule Kalcifer.Channels.Providers.LogProviderTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Channels.Providers.LogProvider

  test "send_message returns ok with a delivery_id" do
    recipient = %{"email" => "test@example.com"}
    message = %{"template_id" => "welcome"}

    assert {:ok, delivery_id} = LogProvider.send_message(:email, recipient, message, %{})
    assert is_binary(delivery_id)
  end

  test "delivery_status returns ok" do
    assert {:ok, _status} = LogProvider.delivery_status("some_id")
  end
end
