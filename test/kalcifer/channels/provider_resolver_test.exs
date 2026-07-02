defmodule Kalcifer.Channels.ProviderResolverTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Channels.Providers.LogProvider
  alias Kalcifer.Channels.Providers.SendgridProvider
  alias Kalcifer.Channels.ProviderResolver

  defp with_provider(channel, entry) do
    insert(:tenant, settings: %{"channel_providers" => %{channel => entry}})
  end

  describe "resolve/3 — per-tenant selection" do
    test "picks the tenant's configured provider module and merges its config" do
      tenant =
        with_provider("email", %{
          "provider" => "sendgrid",
          "config" => %{"api_key" => "sk_tenant", "from" => "tenant@x.com"}
        })

      assert {:ok, resolution} =
               ProviderResolver.resolve(:email, tenant.id, %{"subject" => "Hi"})

      assert resolution.provider_name == "sendgrid"
      assert resolution.provider_module == SendgridProvider
      # tenant config + node opts are merged into provider_opts
      assert resolution.provider_opts["api_key"] == "sk_tenant"
      assert resolution.provider_opts["from"] == "tenant@x.com"
      assert resolution.provider_opts["subject"] == "Hi"
    end

    test "node opts win over tenant config on key conflict" do
      tenant =
        with_provider("email", %{
          "provider" => "sendgrid",
          "config" => %{"from" => "tenant@x.com"}
        })

      assert {:ok, resolution} =
               ProviderResolver.resolve(:email, tenant.id, %{"from" => "node@x.com"})

      assert resolution.provider_opts["from"] == "node@x.com"
    end

    test "accepts a string channel as well as an atom" do
      tenant = with_provider("email", %{"provider" => "sendgrid"})

      assert {:ok, %{provider_name: "sendgrid"}} =
               ProviderResolver.resolve("email", tenant.id, %{})
    end
  end

  describe "resolve/3 — registry fallback" do
    test "falls back to the registry default when the tenant has no entry" do
      tenant = insert(:tenant)

      assert {:ok, resolution} = ProviderResolver.resolve(:email, tenant.id, %{"a" => 1})

      assert resolution.provider_name == nil
      assert resolution.provider_module == LogProvider
      assert resolution.provider_opts == %{"a" => 1}
    end

    test "falls back when the tenant entry is disabled" do
      tenant =
        with_provider("email", %{"provider" => "sendgrid", "enabled" => false})

      assert {:ok, %{provider_name: nil, provider_module: LogProvider}} =
               ProviderResolver.resolve(:email, tenant.id, %{})
    end

    test "falls back when the tenant names an unknown provider" do
      tenant = with_provider("email", %{"provider" => "does_not_exist"})

      assert {:ok, %{provider_name: nil, provider_module: LogProvider}} =
               ProviderResolver.resolve(:email, tenant.id, %{})
    end

    test "falls back when tenant_id is nil" do
      assert {:ok, %{provider_name: nil, provider_module: LogProvider}} =
               ProviderResolver.resolve(:email, nil, %{})
    end

    test "returns :error when no provider is configured anywhere" do
      tenant = insert(:tenant)

      assert :error = ProviderResolver.resolve(:unknown_channel, tenant.id, %{})
    end
  end

  describe "module_for/1" do
    test "maps a known provider name to its module" do
      assert ProviderResolver.module_for("sendgrid") == SendgridProvider
      assert ProviderResolver.module_for("log") == LogProvider
    end

    test "returns nil for an unknown name" do
      assert ProviderResolver.module_for("nope") == nil
    end
  end
end
