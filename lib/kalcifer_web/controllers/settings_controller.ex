defmodule KalciferWeb.SettingsController do
  use KalciferWeb, :controller

  alias Kalcifer.Tenants
  alias Kalcifer.Tenants.Tenant

  @doc """
  GET /api/v1/settings

  Returns the current tenant's settings (AI model, available models, etc.).
  Sensitive fields (like API key) are masked.
  """
  def show(conn, _params) do
    tenant_id = resolve_dev_tenant(conn)

    case Tenants.get_tenant(tenant_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Tenant not found"})

      tenant ->
        json(conn, settings_response(tenant))
    end
  end

  @doc """
  PUT /api/v1/settings

  Updates tenant settings. Accepts:
    - `ai_model`: one of the available models
    - `ai_api_key`: legacy single key (backward compat)
    - `provider_key`: %{"provider" => "anthropic", "key" => "sk-..."}
    - `remove_provider_key`: "anthropic" (removes that provider's key)
  """
  def update(conn, params) do
    tenant_id = resolve_dev_tenant(conn)

    case Tenants.get_tenant(tenant_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Tenant not found"})

      tenant ->
        settings = build_settings_update(tenant, params)

        case Tenants.update_settings(tenant, settings) do
          {:ok, updated} ->
            json(conn, settings_response(updated))

          {:error, changeset} ->
            KalciferWeb.FallbackController.call(conn, {:error, changeset})
        end
    end
  end

  defp build_settings_update(tenant, params) do
    settings = %{}
    settings = maybe_put(settings, "ai_model", params["ai_model"])
    # Legacy single key support
    settings = maybe_put(settings, "ai_api_key", params["ai_api_key"])

    # Per-provider key: {"provider" => "anthropic", "key" => "sk-..."}
    settings =
      case params["provider_key"] do
        %{"provider" => provider, "key" => key} when is_binary(provider) ->
          existing_keys = Map.get(tenant.settings || %{}, "ai_keys", %{})
          updated_keys = Map.put(existing_keys, provider, key)
          Map.put(settings, "ai_keys", updated_keys)

        _ ->
          settings
      end

    # Remove provider key: "anthropic"
    settings =
      case params["remove_provider_key"] do
        provider when is_binary(provider) ->
          existing_keys = Map.get(tenant.settings || %{}, "ai_keys", %{})
          updated_keys = Map.delete(existing_keys, provider)
          Map.put(settings, "ai_keys", updated_keys)

        _ ->
          settings
      end

    # Channel provider config: {"channel" => "email", "provider" => "sendgrid", "config" => {...}}
    settings =
      case params["channel_provider"] do
        %{"channel" => channel, "provider" => provider} = cp when is_binary(channel) ->
          existing = Map.get(tenant.settings || %{}, "channel_providers", %{})
          config = Map.get(cp, "config", %{})

          updated =
            Map.put(existing, channel, %{
              "provider" => provider,
              "config" => config,
              "enabled" => Map.get(cp, "enabled", true)
            })

          Map.put(settings, "channel_providers", updated)

        _ ->
          settings
      end

    # Remove channel provider: "email"
    settings =
      case params["remove_channel_provider"] do
        channel when is_binary(channel) ->
          existing = Map.get(tenant.settings || %{}, "channel_providers", %{})
          updated = Map.delete(existing, channel)
          Map.put(settings, "channel_providers", updated)

        _ ->
          settings
      end

    settings
  end

  defp settings_response(tenant) do
    ai = Tenants.ai_config(tenant)
    provider_keys = Tenants.provider_keys(tenant)
    channel_providers = channel_providers_response(tenant)

    %{
      ai_model: ai.model || default_model(),
      ai_provider: ai.provider,
      ai_api_key_set: ai.api_key != nil and ai.api_key != "",
      provider_keys: provider_keys,
      available_models: available_models(),
      channel_providers: channel_providers
    }
  end

  defp channel_providers_response(tenant) do
    providers = Map.get(tenant.settings || %{}, "channel_providers", %{})

    default_channels = %{
      "email" => %{"provider" => "log", "enabled" => true},
      "sms" => %{"provider" => "log", "enabled" => true},
      "push" => %{"provider" => "log", "enabled" => true},
      "whatsapp" => %{"provider" => "log", "enabled" => true},
      "webhook" => %{"provider" => "log", "enabled" => true}
    }

    Map.merge(default_channels, providers)
    |> Enum.map(fn {channel, config} ->
      %{
        channel: channel,
        provider: config["provider"] || "log",
        enabled: Map.get(config, "enabled", true),
        configured: config["provider"] != nil and config["provider"] != "log"
      }
    end)
    |> Enum.sort_by(& &1.channel)
  end

  @doc """
  POST /api/v1/settings/regenerate-api-key

  Generates a new API key for the tenant. Returns the raw key ONCE.
  """
  def regenerate_api_key(conn, _params) do
    tenant_id = resolve_dev_tenant(conn)

    case Tenants.get_tenant(tenant_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Tenant not found"})

      tenant ->
        case Tenants.regenerate_api_key(tenant) do
          {:ok, raw_key, _updated} ->
            json(conn, %{
              api_key: raw_key,
              message: "ახალი API key შეიქმნა. შეინახეთ — ეს ერთადერთხელ ჩანს!"
            })

          {:error, _changeset} ->
            conn |> put_status(422) |> json(%{error: "Failed to regenerate key"})
        end
    end
  end

  @doc """
  GET /api/v1/settings/stats

  Basic monitoring: conversation count, tool usage, flow count.
  """
  def stats(conn, _params) do
    tenant_id = resolve_dev_tenant(conn)

    alias Kalcifer.Repo
    import Ecto.Query

    conversation_count =
      from(c in Kalcifer.AI.Conversation, where: c.tenant_id == ^tenant_id)
      |> Repo.aggregate(:count)

    active_conversations =
      from(c in Kalcifer.AI.Conversation,
        where: c.tenant_id == ^tenant_id and c.status == "active"
      )
      |> Repo.aggregate(:count)

    message_count =
      from(m in Kalcifer.AI.ConversationMessage,
        join: c in Kalcifer.AI.Conversation,
        on: m.conversation_id == c.id,
        where: c.tenant_id == ^tenant_id
      )
      |> Repo.aggregate(:count)

    flow_count =
      from(f in Kalcifer.Flows.Flow, where: f.tenant_id == ^tenant_id)
      |> Repo.aggregate(:count)

    active_flows =
      from(f in Kalcifer.Flows.Flow,
        where: f.tenant_id == ^tenant_id and f.status == "active"
      )
      |> Repo.aggregate(:count)

    memory_count =
      from(m in Kalcifer.AI.Memory, where: m.tenant_id == ^tenant_id)
      |> Repo.aggregate(:count)

    json(conn, %{
      conversations: %{total: conversation_count, active: active_conversations},
      messages: %{total: message_count},
      flows: %{total: flow_count, active: active_flows},
      memories: %{total: memory_count}
    })
  end

  defp available_models do
    Tenant.valid_ai_models()
    |> Enum.map(fn {provider, models} ->
      %{
        provider: provider,
        display_name: provider_display_name(provider),
        models:
          Enum.map(models, fn model ->
            %{id: model, name: model_display_name(model)}
          end)
      }
    end)
    |> Enum.sort_by(fn p -> provider_order(p.provider) end)
  end

  defp provider_display_name("anthropic"), do: "Claude"
  defp provider_display_name("openai"), do: "ChatGPT"
  defp provider_display_name("google"), do: "Gemini"
  defp provider_display_name(other), do: other

  defp provider_order("anthropic"), do: 0
  defp provider_order("openai"), do: 1
  defp provider_order("google"), do: 2
  defp provider_order(_), do: 9

  defp model_display_name("claude-haiku-4-5-20251001"), do: "Claude Haiku 4.5"
  defp model_display_name("claude-sonnet-4-6"), do: "Claude Sonnet 4.6"
  defp model_display_name("claude-sonnet-5"), do: "Claude Sonnet 5"
  defp model_display_name("claude-opus-4-8"), do: "Claude Opus 4.8"
  defp model_display_name("gpt-5.5"), do: "GPT-5.5"
  defp model_display_name("gpt-5.4-mini"), do: "GPT-5.4 Mini"
  defp model_display_name("gpt-5.4-nano"), do: "GPT-5.4 Nano"
  defp model_display_name("gemini-3.1-pro-preview"), do: "Gemini 3.1 Pro"
  defp model_display_name("gemini-3.5-flash"), do: "Gemini 3.5 Flash"
  defp model_display_name(other), do: other

  defp default_model, do: "claude-sonnet-5"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp resolve_dev_tenant(conn), do: KalciferWeb.TenantResolver.resolve_id(conn)
end
