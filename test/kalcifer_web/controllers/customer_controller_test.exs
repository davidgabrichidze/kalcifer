defmodule KalciferWeb.CustomerControllerTest do
  use KalciferWeb.ConnCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Tenants

  @raw_api_key "test_key_for_customer_controller"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  describe "index" do
    test "lists customers for tenant", %{conn: conn, tenant: tenant} do
      insert(:customer, tenant: tenant)
      insert(:customer, tenant: tenant)

      conn = get(conn, "/api/v1/customers")
      body = json_response(conn, 200)

      assert length(body["data"]) == 2
    end

    test "does not return other tenant's customers", %{conn: conn} do
      other_tenant = insert(:tenant)
      insert(:customer, tenant: other_tenant)

      conn = get(conn, "/api/v1/customers")
      body = json_response(conn, 200)

      assert body["data"] == []
    end
  end

  describe "create" do
    test "creates a customer with valid attrs", %{conn: conn} do
      conn =
        post(conn, "/api/v1/customers", %{
          "external_id" => "ext_001",
          "email" => "alice@example.com"
        })

      body = json_response(conn, 201)

      assert body["data"]["external_id"] == "ext_001"
      assert body["data"]["email"] == "alice@example.com"
    end

    test "returns 422 when external_id is missing", %{conn: conn} do
      conn = post(conn, "/api/v1/customers", %{"email" => "test@test.com"})
      assert json_response(conn, 422)
    end
  end

  describe "show" do
    test "returns customer by id", %{conn: conn, tenant: tenant} do
      customer = insert(:customer, tenant: tenant)

      conn = get(conn, "/api/v1/customers/#{customer.id}")
      body = json_response(conn, 200)

      assert body["data"]["id"] == customer.id
      assert body["data"]["external_id"] == customer.external_id
    end

    test "returns 404 for other tenant's customer", %{conn: conn} do
      other = insert(:customer, tenant: insert(:tenant))

      conn = get(conn, "/api/v1/customers/#{other.id}")
      assert json_response(conn, 404)
    end

    test "returns 404 for nonexistent customer", %{conn: conn} do
      conn = get(conn, "/api/v1/customers/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "update" do
    test "updates customer fields", %{conn: conn, tenant: tenant} do
      customer = insert(:customer, tenant: tenant, name: "Old Name")

      conn = put(conn, "/api/v1/customers/#{customer.id}", %{"name" => "New Name"})
      body = json_response(conn, 200)

      assert body["data"]["name"] == "New Name"
    end

    test "returns 404 for other tenant's customer", %{conn: conn} do
      other = insert(:customer, tenant: insert(:tenant))

      conn = put(conn, "/api/v1/customers/#{other.id}", %{"name" => "Hack"})
      assert json_response(conn, 404)
    end
  end

  describe "add_tags" do
    test "adds tags to customer", %{conn: conn, tenant: tenant} do
      customer = insert(:customer, tenant: tenant, tags: ["existing"])

      conn =
        post(conn, "/api/v1/customers/#{customer.id}/tags", %{
          "customer_id" => customer.id,
          "tags" => ["vip", "priority"]
        })

      body = json_response(conn, 200)
      tags = body["data"]["tags"]

      assert "vip" in tags
      assert "priority" in tags
      assert "existing" in tags
    end

    test "returns 404 for other tenant's customer", %{conn: conn} do
      other = insert(:customer, tenant: insert(:tenant))

      conn =
        post(conn, "/api/v1/customers/#{other.id}/tags", %{"customer_id" => other.id, "tags" => ["vip"]})

      assert json_response(conn, 404)
    end
  end

  describe "update_preferences" do
    test "merges customer preferences", %{conn: conn, tenant: tenant} do
      customer = insert(:customer, tenant: tenant, preferences: %{"email" => true})

      conn =
        put(conn, "/api/v1/customers/#{customer.id}/preferences", %{
          "customer_id" => customer.id,
          "preferences" => %{"sms" => false}
        })

      body = json_response(conn, 200)
      prefs = body["data"]["preferences"]

      assert prefs["email"] == true
      assert prefs["sms"] == false
    end
  end

  describe "authentication" do
    test "returns 401 without API key", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> get("/api/v1/customers")

      assert json_response(conn, 401)
    end
  end
end
