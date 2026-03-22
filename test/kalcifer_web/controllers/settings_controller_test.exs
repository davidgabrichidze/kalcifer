defmodule KalciferWeb.SettingsControllerTest do
  use KalciferWeb.ConnCase, async: true

  alias Kalcifer.AI.Context
  alias Kalcifer.Tenants

  import Kalcifer.Factory

  setup do
    tenant = insert(:tenant, name: "Demo Tenant")
    %{tenant: tenant}
  end

  describe "GET /api/v1/settings" do
    test "returns default settings", %{conn: conn} do
      conn = get(conn, "/api/v1/settings")
      result = json_response(conn, 200)

      assert result["ai_model"] == "claude-haiku-4-5-20251001"
      assert result["ai_api_key_set"] == false
      assert is_list(result["available_models"])
      assert length(result["available_models"]) >= 3
    end

    test "returns tenant-specific model after update", %{conn: conn, tenant: tenant} do
      Tenants.update_settings(tenant, %{"ai_model" => "claude-sonnet-4-6"})

      conn = get(conn, "/api/v1/settings")
      result = json_response(conn, 200)
      assert result["ai_model"] == "claude-sonnet-4-6"
    end

    test "shows api_key_set as true when key is configured", %{conn: conn, tenant: tenant} do
      Tenants.update_settings(tenant, %{"ai_api_key" => "sk-ant-test123"})

      conn = get(conn, "/api/v1/settings")
      result = json_response(conn, 200)
      assert result["ai_api_key_set"] == true
    end

    test "available_models have id and name fields", %{conn: conn} do
      conn = get(conn, "/api/v1/settings")
      result = json_response(conn, 200)

      for model <- result["available_models"] do
        assert Map.has_key?(model, "id")
        assert Map.has_key?(model, "name")
      end
    end
  end

  describe "PUT /api/v1/settings" do
    test "updates AI model", %{conn: conn} do
      conn = put(conn, "/api/v1/settings", %{"ai_model" => "claude-sonnet-4-6"})
      result = json_response(conn, 200)
      assert result["ai_model"] == "claude-sonnet-4-6"
    end

    test "updates API key", %{conn: conn} do
      conn = put(conn, "/api/v1/settings", %{"ai_api_key" => "sk-ant-new-key"})
      result = json_response(conn, 200)
      assert result["ai_api_key_set"] == true
    end

    test "removes API key with empty string", %{conn: conn, tenant: tenant} do
      Tenants.update_settings(tenant, %{"ai_api_key" => "sk-ant-test"})

      conn = put(conn, "/api/v1/settings", %{"ai_api_key" => ""})
      result = json_response(conn, 200)
      assert result["ai_api_key_set"] == false
    end

    test "rejects invalid model", %{conn: conn} do
      conn = put(conn, "/api/v1/settings", %{"ai_model" => "gpt-4"})
      assert json_response(conn, 422)["errors"]
    end

    test "partial update — model change does not clear api_key", %{conn: conn, tenant: tenant} do
      Tenants.update_settings(tenant, %{"ai_api_key" => "sk-ant-keep"})

      conn = put(conn, "/api/v1/settings", %{"ai_model" => "claude-sonnet-4-6"})
      result = json_response(conn, 200)
      assert result["ai_model"] == "claude-sonnet-4-6"
      assert result["ai_api_key_set"] == true
    end
  end

  describe "GET /api/v1/settings/stats" do
    test "returns stats structure", %{conn: conn} do
      conn = get(conn, "/api/v1/settings/stats")
      result = json_response(conn, 200)

      assert is_map(result["conversations"])
      assert is_integer(result["conversations"]["total"])
      assert is_integer(result["conversations"]["active"])
      assert is_map(result["messages"])
      assert is_map(result["flows"])
      assert is_map(result["memories"])
    end

    test "counts conversations correctly", %{conn: conn, tenant: tenant} do
      {:ok, _} = Context.create_conversation(tenant.id)
      {:ok, _} = Context.create_conversation(tenant.id)

      conn = get(conn, "/api/v1/settings/stats")
      result = json_response(conn, 200)
      assert result["conversations"]["total"] >= 2
      assert result["conversations"]["active"] >= 2
    end

    test "counts flows correctly", %{conn: conn, tenant: tenant} do
      insert(:flow, tenant: tenant, status: "draft")
      insert(:flow, tenant: tenant, status: "active")

      conn = get(conn, "/api/v1/settings/stats")
      result = json_response(conn, 200)
      assert result["flows"]["total"] >= 2
      assert result["flows"]["active"] >= 1
    end
  end
end
