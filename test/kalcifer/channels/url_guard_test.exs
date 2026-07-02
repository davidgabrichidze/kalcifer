defmodule Kalcifer.Channels.UrlGuardTest do
  # async: false — toggles the global :allow_private_webhooks flag
  use ExUnit.Case, async: false

  alias Kalcifer.Channels.UrlGuard

  setup do
    previous = Application.get_env(:kalcifer, :allow_private_webhooks, false)
    Application.put_env(:kalcifer, :allow_private_webhooks, false)
    on_exit(fn -> Application.put_env(:kalcifer, :allow_private_webhooks, previous) end)
    :ok
  end

  test "allows a public https URL" do
    assert :ok = UrlGuard.validate("https://example.com/webhook")
  end

  test "blocks cloud metadata address" do
    assert {:error, :blocked_address} =
             UrlGuard.validate("http://169.254.169.254/latest/meta-data/")
  end

  test "blocks loopback" do
    assert {:error, :blocked_address} = UrlGuard.validate("http://127.0.0.1:4000/hook")
    assert {:error, :blocked_address} = UrlGuard.validate("http://[::1]:4000/hook")
  end

  test "blocks RFC1918 private ranges" do
    assert {:error, :blocked_address} = UrlGuard.validate("http://10.0.0.5/x")
    assert {:error, :blocked_address} = UrlGuard.validate("http://192.168.1.10/x")
    assert {:error, :blocked_address} = UrlGuard.validate("http://172.16.0.1/x")
  end

  test "blocks non-http schemes" do
    assert {:error, :unsupported_scheme} = UrlGuard.validate("file:///etc/passwd")
    assert {:error, :unsupported_scheme} = UrlGuard.validate("gopher://evil/")
  end

  test "rejects malformed URLs" do
    assert {:error, :invalid_url} = UrlGuard.validate("not a url")
    assert {:error, :invalid_url} = UrlGuard.validate(nil)
  end

  test "allows private hosts when the flag is on" do
    Application.put_env(:kalcifer, :allow_private_webhooks, true)
    assert :ok = UrlGuard.validate("http://127.0.0.1:4000/hook")
  end
end
