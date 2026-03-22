defmodule Kalcifer.TenantsTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Tenants

  import Kalcifer.Factory

  describe "ai_config/1" do
    test "returns nil values when no AI settings" do
      tenant = insert(:tenant)
      config = Tenants.ai_config(tenant)
      assert config.model == nil
      assert config.api_key == nil
    end

    test "returns configured model and key" do
      tenant = insert(:tenant, settings: %{"ai_model" => "claude-sonnet-4-6", "ai_api_key" => "sk-test"})
      config = Tenants.ai_config(tenant)
      assert config.model == "claude-sonnet-4-6"
      assert config.api_key == "sk-test"
    end
  end

  describe "update_settings/2" do
    test "merges new settings with existing" do
      tenant = insert(:tenant, settings: %{"ai_model" => "claude-haiku-4-5-20251001"})
      {:ok, updated} = Tenants.update_settings(tenant, %{"ai_api_key" => "sk-new"})

      assert updated.settings["ai_model"] == "claude-haiku-4-5-20251001"
      assert updated.settings["ai_api_key"] == "sk-new"
    end

    test "overwrites specific keys" do
      tenant = insert(:tenant, settings: %{"ai_model" => "claude-haiku-4-5-20251001"})
      {:ok, updated} = Tenants.update_settings(tenant, %{"ai_model" => "claude-sonnet-4-6"})
      assert updated.settings["ai_model"] == "claude-sonnet-4-6"
    end

    test "rejects invalid AI model" do
      tenant = insert(:tenant)
      assert {:error, changeset} = Tenants.update_settings(tenant, %{"ai_model" => "gpt-4"})
      assert %{settings: _} = errors_on(changeset)
    end

    test "accepts all valid models" do
      tenant = insert(:tenant)

      for model <- Kalcifer.Tenants.Tenant.valid_ai_models() do
        {:ok, updated} = Tenants.update_settings(tenant, %{"ai_model" => model})
        assert updated.settings["ai_model"] == model
      end
    end

    test "preserves other settings keys" do
      tenant = insert(:tenant, settings: %{"custom_key" => "value"})
      {:ok, updated} = Tenants.update_settings(tenant, %{"ai_model" => "claude-sonnet-4-6"})

      assert updated.settings["custom_key"] == "value"
      assert updated.settings["ai_model"] == "claude-sonnet-4-6"
    end
  end

  describe "get_setting/3" do
    test "returns setting value" do
      tenant = insert(:tenant, settings: %{"ai_model" => "claude-sonnet-4-6"})
      assert Tenants.get_setting(tenant, "ai_model") == "claude-sonnet-4-6"
    end

    test "returns default for missing key" do
      tenant = insert(:tenant)
      assert Tenants.get_setting(tenant, "missing", "fallback") == "fallback"
    end

    test "returns nil for missing key without default" do
      tenant = insert(:tenant)
      assert Tenants.get_setting(tenant, "missing") == nil
    end
  end
end
