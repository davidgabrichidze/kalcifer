defmodule Kalcifer.Channels.ProviderResolver do
  @moduledoc """
  Resolves which provider module and options to use for a channel send,
  honoring per-tenant configuration stored in `tenant.settings`:

      "channel_providers" => %{
        "email" => %{"provider" => "sendgrid", "config" => %{...}, "enabled" => true}
      }

  A named provider ("sendgrid", "twilio", "log", "webhook", ...) maps to a
  module via `config :kalcifer, :provider_modules`. When the tenant has no
  entry (or it's disabled/unknown), falls back to the global
  `ProviderRegistry` default for the channel.

  Resolution never mutates global state, so concurrent sends for different
  tenants can't clobber each other's provider selection.
  """

  alias Kalcifer.Channels.ProviderRegistry
  alias Kalcifer.Tenants

  @type resolution :: %{
          provider_name: String.t() | nil,
          provider_module: module(),
          provider_opts: map()
        }

  @doc """
  Returns `{:ok, resolution}` when a provider is available for the channel,
  or `:error` when none is configured anywhere. `provider_opts` merges the
  tenant's per-channel config under the node's own opts (node opts win).
  """
  @spec resolve(String.t() | atom(), String.t() | nil, map()) :: {:ok, resolution} | :error
  def resolve(channel, tenant_id, node_opts) do
    channel_str = to_string(channel)
    channel_atom = to_atom(channel)

    case tenant_provider(tenant_id, channel_str) do
      {name, module, config} ->
        {:ok,
         %{
           provider_name: name,
           provider_module: module,
           provider_opts: Map.merge(config, node_opts)
         }}

      nil ->
        case ProviderRegistry.lookup(channel_atom) do
          {:ok, module} ->
            {:ok, %{provider_name: nil, provider_module: module, provider_opts: node_opts}}

          :error ->
            :error
        end
    end
  end

  @doc "Maps a provider name string to its module, or nil if unknown."
  def module_for(name) do
    :kalcifer
    |> Application.get_env(:provider_modules, %{})
    |> Map.get(name)
  end

  defp tenant_provider(nil, _channel), do: nil

  defp tenant_provider(tenant_id, channel) do
    with %{} = tenant <- Tenants.get_tenant(tenant_id),
         providers when is_map(providers) <-
           Map.get(tenant.settings || %{}, "channel_providers"),
         %{"provider" => name} = entry <- Map.get(providers, channel),
         true <- Map.get(entry, "enabled", true),
         module when not is_nil(module) <- module_for(name) do
      {name, module, Map.get(entry, "config", %{})}
    else
      _ -> nil
    end
  end

  defp to_atom(channel) when is_atom(channel), do: channel
  defp to_atom(channel) when is_binary(channel), do: String.to_existing_atom(channel)
end
