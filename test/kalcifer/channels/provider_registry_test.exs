defmodule Kalcifer.Channels.ProviderRegistryTest do
  use ExUnit.Case, async: false

  alias Kalcifer.Channels.ProviderRegistry

  test "lookup returns provider for configured channel" do
    assert {:ok, Kalcifer.Channels.Providers.LogProvider} = ProviderRegistry.lookup(:email)
  end

  test "lookup returns :error for unconfigured channel" do
    assert :error = ProviderRegistry.lookup(:carrier_pigeon)
  end

  test "register adds a new provider at runtime" do
    ProviderRegistry.register(:test_channel, Kalcifer.Channels.Providers.LogProvider)
    assert {:ok, Kalcifer.Channels.Providers.LogProvider} = ProviderRegistry.lookup(:test_channel)
  end

  test "list_all returns all registered providers" do
    providers = ProviderRegistry.list_all()
    assert length(providers) >= 6
  end
end
