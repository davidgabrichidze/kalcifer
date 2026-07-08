defmodule Kalcifer.Tenants.Tenant do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tenants" do
    field :name, :string
    field :api_key_hash, :string
    field :settings, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @valid_ai_models %{
    "anthropic" => ~w(
      claude-haiku-4-5-20251001
      claude-sonnet-4-6
      claude-sonnet-5
      claude-opus-4-8
    ),
    "openai" => ~w(
      gpt-5.5
      gpt-5.4-mini
      gpt-5.4-nano
    ),
    "google" => ~w(
      gemini-3.1-pro-preview
      gemini-3.5-flash
    )
  }

  def valid_ai_models, do: @valid_ai_models

  def all_model_ids do
    @valid_ai_models |> Map.values() |> List.flatten()
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :api_key_hash, :settings])
    |> validate_required([:name, :api_key_hash])
    |> unique_constraint(:name)
    |> unique_constraint(:api_key_hash)
  end

  def settings_changeset(tenant, settings) when is_map(settings) do
    tenant
    |> cast(%{settings: settings}, [:settings])
    |> validate_ai_model()
  end

  defp validate_ai_model(changeset) do
    case get_change(changeset, :settings) do
      nil ->
        changeset

      settings ->
        case Map.get(settings, "ai_model") do
          nil ->
            changeset

          model ->
            if model in all_model_ids() do
              changeset
            else
              add_error(changeset, :settings, "invalid AI model: #{model}")
            end
        end
    end
  end
end
