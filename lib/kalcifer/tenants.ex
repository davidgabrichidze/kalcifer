defmodule Kalcifer.Tenants do
  @moduledoc false

  alias Kalcifer.Repo
  alias Kalcifer.Tenants.Tenant

  def get_tenant(id), do: Repo.get(Tenant, id)

  def get_tenant_by_api_key_hash(hash) do
    Repo.get_by(Tenant, api_key_hash: hash)
  end

  def create_tenant(attrs) do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert()
  end

  def hash_api_key(raw_key) do
    :crypto.hash(:sha256, raw_key) |> Base.encode16(case: :lower)
  end

  # ── Settings ──────────────────────────────────────────────────

  @doc "Update tenant settings (partial merge — only overwrites keys you pass)."
  def update_settings(%Tenant{} = tenant, new_settings) when is_map(new_settings) do
    merged = Map.merge(tenant.settings || %{}, new_settings)

    tenant
    |> Tenant.settings_changeset(merged)
    |> Repo.update()
  end

  @doc "Get a specific setting with fallback."
  def get_setting(%Tenant{settings: settings}, key, default \\ nil) do
    Map.get(settings || %{}, key, default)
  end

  @doc "Get AI-specific settings: model, provider, and api_key for active provider."
  def ai_config(%Tenant{} = tenant) do
    settings = tenant.settings || %{}
    model = Map.get(settings, "ai_model")
    provider = provider_for_model(model)
    keys = Map.get(settings, "ai_keys", %{})

    # Per-provider key takes priority, fall back to legacy ai_api_key
    api_key = Map.get(keys, provider) || Map.get(settings, "ai_api_key")

    %{
      model: model,
      provider: provider,
      api_key: api_key
    }
  end

  @doc "Get per-provider API keys (masked — only returns which providers have keys set)."
  def provider_keys(%Tenant{} = tenant) do
    keys = Map.get(tenant.settings || %{}, "ai_keys", %{})

    keys
    |> Enum.map(fn {provider, key} ->
      {provider, key != nil and key != ""}
    end)
    |> Map.new()
  end

  @doc "Determine which provider a model belongs to."
  def provider_for_model(nil), do: "anthropic"

  def provider_for_model(model) do
    Tenant.valid_ai_models()
    |> Enum.find_value("anthropic", fn {provider, models} ->
      if model in models, do: provider
    end)
  end
end
