defmodule KalciferWeb.SegmentControllerTest do
  use KalciferWeb.ConnCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Tenants

  @raw_api_key "test_key_for_segment_controller"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  describe "CRUD" do
    test "creates, lists, shows, updates and deletes a segment", %{conn: conn} do
      create_resp =
        post(conn, "/api/v1/segments", %{
          "name" => "VIP",
          "rules" => [%{"field" => "tags", "operator" => "contains", "value" => "vip"}]
        })

      created = json_response(create_resp, 201)["data"]
      assert created["name"] == "VIP"
      assert [%{"field" => "tags"}] = created["rules"]

      assert [%{"id" => id}] = json_response(get(conn, "/api/v1/segments"), 200)["data"]
      assert id == created["id"]

      show = json_response(get(conn, "/api/v1/segments/#{id}"), 200)["data"]
      assert show["type"] == "dynamic"

      updated_resp = put(conn, "/api/v1/segments/#{id}", %{"name" => "VIP v2"})
      assert json_response(updated_resp, 200)["data"]["name"] == "VIP v2"

      assert response(delete(conn, "/api/v1/segments/#{id}"), 204)
      assert json_response(get(conn, "/api/v1/segments/#{id}"), 404)
    end

    test "returns 422 for invalid segment", %{conn: conn} do
      resp = post(conn, "/api/v1/segments", %{"type" => "weird"})
      assert json_response(resp, 422)
    end

    test "cannot access another tenant's segment", %{conn: conn} do
      other = insert(:segment)

      assert json_response(get(conn, "/api/v1/segments/#{other.id}"), 404)
      assert json_response(put(conn, "/api/v1/segments/#{other.id}", %{"name" => "x"}), 404)
      assert json_response(delete(conn, "/api/v1/segments/#{other.id}"), 404)
    end
  end

  describe "members" do
    test "lists members evaluated from rules with total meta", %{conn: conn, tenant: tenant} do
      insert(:customer, tenant: tenant, tags: ["vip"], name: "Anna")
      insert(:customer, tenant: tenant, tags: [], name: "Beka")

      segment =
        insert(:segment,
          tenant: tenant,
          rules: [%{"field" => "tags", "operator" => "contains", "value" => "vip"}]
        )

      body = json_response(get(conn, "/api/v1/segments/#{segment.id}/members"), 200)

      assert body["meta"]["total"] == 1
      assert [%{"name" => "Anna"}] = body["data"]
    end

    test "supports limit/offset pagination", %{conn: conn, tenant: tenant} do
      for _ <- 1..3, do: insert(:customer, tenant: tenant, tags: ["vip"])

      segment =
        insert(:segment,
          tenant: tenant,
          rules: [%{"field" => "tags", "operator" => "contains", "value" => "vip"}]
        )

      body =
        json_response(get(conn, "/api/v1/segments/#{segment.id}/members?limit=2&offset=2"), 200)

      assert body["meta"]["total"] == 3
      assert length(body["data"]) == 1
    end
  end
end
