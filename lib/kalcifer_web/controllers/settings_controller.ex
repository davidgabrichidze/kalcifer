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
    tenant_id = resolve_dev_tenant()

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
    tenant_id = resolve_dev_tenant()

    case Tenants.get_tenant(tenant_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Tenant not found"})

      tenant ->
        settings = build_settings_update(tenant, params)

        case Tenants.update_settings(tenant, settings) do
          {:ok, updated} ->
            json(conn, settings_response(updated))

          {:error, changeset} ->
            errors =
              Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

            conn |> put_status(422) |> json(%{errors: errors})
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

    settings
  end

  defp settings_response(tenant) do
    ai = Tenants.ai_config(tenant)
    provider_keys = Tenants.provider_keys(tenant)

    %{
      ai_model: ai.model || default_model(),
      ai_provider: ai.provider,
      ai_api_key_set: ai.api_key != nil and ai.api_key != "",
      provider_keys: provider_keys,
      available_models: available_models()
    }
  end

  @doc """
  GET /api/v1/settings/stats

  Basic monitoring: conversation count, tool usage, flow count.
  """
  def stats(conn, _params) do
    tenant_id = resolve_dev_tenant()

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
  defp model_display_name("claude-sonnet-4-5-20250514"), do: "Claude Sonnet 4.5"
  defp model_display_name("claude-sonnet-4-6"), do: "Claude Sonnet 4.6"
  defp model_display_name("gpt-4o"), do: "GPT-4o"
  defp model_display_name("gpt-4o-mini"), do: "GPT-4o Mini"
  defp model_display_name("o3-mini"), do: "o3-mini"
  defp model_display_name("gemini-2.5-pro"), do: "Gemini 2.5 Pro"
  defp model_display_name("gemini-2.5-flash"), do: "Gemini 2.5 Flash"
  defp model_display_name(other), do: other

  defp default_model, do: "claude-haiku-4-5-20251001"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Same dev tenant resolution as ChatController
  defp resolve_dev_tenant do
    alias Kalcifer.Repo

    case Repo.get_by(Tenant, name: "Demo Tenant") do
      %Tenant{id: id} -> id
      nil ->
        {:ok, tenant} =
          Tenants.create_tenant(%{
            name: "Demo Tenant",
            api_key_hash: Tenants.hash_api_key("demo-dev-key")
          })

        tenant.id
    end
  end
end
