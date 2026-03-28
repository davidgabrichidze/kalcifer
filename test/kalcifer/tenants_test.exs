defmodule Kalcifer.TenantsTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Tenants

  import Kalcifer.Factory

  describe "create_tenant/1" do
    test "creates a tenant with required fields" do
      raw_key = "raw_key_#{System.unique_integer()}"
      hash = Tenants.hash_api_key(raw_key)

      {:ok, tenant} = Tenants.create_tenant(%{name: "Acme Corp", api_key_hash: hash})
      assert tenant.name == "Acme Corp"
      assert tenant.api_key_hash == hash
    end

    test "fails without name" do
      assert {:error, changeset} = Tenants.create_tenant(%{api_key_hash: "hash"})
      assert %{name: _} = errors_on(changeset)
    end
  end

  describe "hash_api_key/1" do
    test "returns deterministic SHA-256 hex hash" do
      assert Tenants.hash_api_key("secret") == Tenants.hash_api_key("secret")
    end

    test "produces different hashes for different inputs" do
      refute Tenants.hash_api_key("key_a") == Tenants.hash_api_key("key_b")
    end

    test "returns 64-character hex string" do
      hash = Tenants.hash_api_key("any_key")
      assert String.length(hash) == 64
      assert hash =~ ~r/^[a-f0-9]+$/
    end
  end

  describe "get_tenant_by_api_key_hash/1" do
    test "returns tenant matching hash" do
      tenant = insert(:tenant)
      found = Tenants.get_tenant_by_api_key_hash(tenant.api_key_hash)
      assert found.id == tenant.id
    end

    test "returns nil for unknown hash" do
      assert Tenants.get_tenant_by_api_key_hash("nonexistent_hash") == nil
    end
  end

  describe "ai_config/1" do
    test "returns nil values when no AI settings" do
      tenant = insert(:tenant)
      config = Tenants.ai_config(tenant)
      assert config.model == nil
      assert config.api_key == nil
    end

    test "returns configured model and key" do
      tenant =
        insert(:tenant, settings: %{"ai_model" => "claude-sonnet-4-6", "ai_api_key" => "sk-test"})

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

      for model <- Kalcifer.Tenants.Tenant.all_model_ids() do
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
