defmodule KalciferWeb.JourneyControllerTest do
  use KalciferWeb.ConnCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Tenants

  @raw_api_key "test_key_for_journey_controller"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)
    flow = insert(:flow, tenant: tenant)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant, flow: flow}
  end

  describe "index" do
    test "lists journeys for tenant", %{conn: conn, tenant: tenant, flow: flow} do
      insert(:journey, tenant: tenant, flow: flow, name: "Journey A")
      insert(:journey, tenant: tenant, flow: flow, name: "Journey B")

      conn = get(conn, "/api/v1/journeys")
      body = json_response(conn, 200)

      assert length(body["data"]) == 2
    end

    test "does not list other tenant's journeys", %{conn: conn} do
      other_tenant = insert(:tenant)
      other_flow = insert(:flow, tenant: other_tenant)
      insert(:journey, tenant: other_tenant, flow: other_flow, name: "Secret Journey")

      conn = get(conn, "/api/v1/journeys")
      body = json_response(conn, 200)

      assert body["data"] == []
    end

    test "filters by status", %{conn: conn, tenant: tenant, flow: flow} do
      insert(:journey, tenant: tenant, flow: flow, status: "draft")
      insert(:journey, tenant: tenant, flow: flow, status: "active")

      conn = get(conn, "/api/v1/journeys?status=active")
      body = json_response(conn, 200)

      assert length(body["data"]) == 1
      assert hd(body["data"])["status"] == "active"
    end
  end

  describe "create" do
    test "creates a journey", %{conn: conn, flow: flow} do
      conn =
        post(conn, "/api/v1/journeys", %{
          "name" => "Welcome Journey",
          "description" => "Onboarding",
          "flow_id" => flow.id
        })

      body = json_response(conn, 201)
      assert body["data"]["name"] == "Welcome Journey"
      assert body["data"]["description"] == "Onboarding"
      assert body["data"]["status"] == "draft"
      assert body["data"]["flow_id"] == flow.id
      assert body["data"]["id"]
    end

    test "returns error for missing name", %{conn: conn, flow: flow} do
      conn = post(conn, "/api/v1/journeys", %{"flow_id" => flow.id})

      assert json_response(conn, 422)["errors"]["name"]
    end

    test "returns error for missing flow_id", %{conn: conn} do
      conn = post(conn, "/api/v1/journeys", %{"name" => "Test"})

      assert json_response(conn, 422)["errors"]["flow_id"]
    end

    test "ignores unknown params", %{conn: conn, flow: flow} do
      conn =
        post(conn, "/api/v1/journeys", %{
          "name" => "Test Journey",
          "flow_id" => flow.id,
          "unknown_field" => "should be ignored",
          "hack" => true
        })

      body = json_response(conn, 201)
      assert body["data"]["name"] == "Test Journey"
    end
  end

  describe "show" do
    test "returns a journey", %{conn: conn, tenant: tenant, flow: flow} do
      journey = insert(:journey, tenant: tenant, flow: flow, name: "My Journey")

      conn = get(conn, "/api/v1/journeys/#{journey.id}")
      body = json_response(conn, 200)

      assert body["data"]["id"] == journey.id
      assert body["data"]["name"] == "My Journey"
    end

    test "returns 404 for other tenant's journey", %{conn: conn} do
      other_tenant = insert(:tenant)
      other_flow = insert(:flow, tenant: other_tenant)
      journey = insert(:journey, tenant: other_tenant, flow: other_flow)

      conn = get(conn, "/api/v1/journeys/#{journey.id}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "returns 404 for non-existent journey", %{conn: conn} do
      conn = get(conn, "/api/v1/journeys/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "update" do
    test "updates a draft journey", %{conn: conn, tenant: tenant, flow: flow} do
      journey = insert(:journey, tenant: tenant, flow: flow, name: "Old Name")

      conn = put(conn, "/api/v1/journeys/#{journey.id}", %{"name" => "New Name"})
      body = json_response(conn, 200)

      assert body["data"]["name"] == "New Name"
    end

    test "updates optional fields", %{conn: conn, tenant: tenant, flow: flow} do
      journey = insert(:journey, tenant: tenant, flow: flow)

      conn =
        put(conn, "/api/v1/journeys/#{journey.id}", %{
          "name" => journey.name,
          "tags" => ["vip", "onboarding"],
          "goal_config" => %{"metric" => "conversion"}
        })

      body = json_response(conn, 200)
      assert body["data"]["tags"] == ["vip", "onboarding"]
      assert body["data"]["goal_config"] == %{"metric" => "conversion"}
    end

    test "rejects update of non-draft journey", %{conn: conn, tenant: tenant, flow: flow} do
      journey = insert(:journey, tenant: tenant, flow: flow, status: "active")

      conn = put(conn, "/api/v1/journeys/#{journey.id}", %{"name" => "Updated"})
      assert json_response(conn, 422) == %{"error" => "journey_not_draft"}
    end

    test "returns 404 for other tenant's journey", %{conn: conn} do
      other_tenant = insert(:tenant)
      other_flow = insert(:flow, tenant: other_tenant)
      journey = insert(:journey, tenant: other_tenant, flow: other_flow)

      conn = put(conn, "/api/v1/journeys/#{journey.id}", %{"name" => "Hacked"})
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "delete" do
    test "deletes a draft journey", %{conn: conn, tenant: tenant, flow: flow} do
      journey = insert(:journey, tenant: tenant, flow: flow)

      conn = delete(conn, "/api/v1/journeys/#{journey.id}")
      assert response(conn, 204)
    end

    test "rejects delete of non-draft journey", %{conn: conn, tenant: tenant, flow: flow} do
      journey = insert(:journey, tenant: tenant, flow: flow, status: "active")

      conn = delete(conn, "/api/v1/journeys/#{journey.id}")
      assert json_response(conn, 422) == %{"error" => "journey_not_draft"}
    end
  end

  describe "launch" do
    test "launches a draft journey", %{conn: conn, tenant: tenant, flow: flow} do
      insert(:flow_version, flow: flow, graph: valid_graph())
      journey = insert(:journey, tenant: tenant, flow: flow)

      conn = post(conn, "/api/v1/journeys/#{journey.id}/launch")
      body = json_response(conn, 200)

      assert body["data"]["status"] == "active"
    end

    test "rejects launch without draft version on flow", %{conn: conn, tenant: tenant, flow: flow} do
      journey = insert(:journey, tenant: tenant, flow: flow)

      conn = post(conn, "/api/v1/journeys/#{journey.id}/launch")
      assert json_response(conn, 422) == %{"error" => "no_draft_version"}
    end

    test "returns 404 for other tenant's journey", %{conn: conn} do
      other_tenant = insert(:tenant)
      other_flow = insert(:flow, tenant: other_tenant)
      journey = insert(:journey, tenant: other_tenant, flow: other_flow)

      conn = post(conn, "/api/v1/journeys/#{journey.id}/launch")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "pause" do
    test "pauses an active journey", %{conn: conn, tenant: tenant, flow: flow} do
      insert(:flow_version, flow: flow, graph: valid_graph())
      journey = insert(:journey, tenant: tenant, flow: flow)
      {:ok, journey} = Kalcifer.Marketing.launch_journey(journey)

      conn = post(conn, "/api/v1/journeys/#{journey.id}/pause")
      body = json_response(conn, 200)

      assert body["data"]["status"] == "paused"
    end
  end

  describe "archive" do
    test "archives an active journey", %{conn: conn, tenant: tenant, flow: flow} do
      insert(:flow_version, flow: flow, graph: valid_graph())
      journey = insert(:journey, tenant: tenant, flow: flow)
      {:ok, journey} = Kalcifer.Marketing.launch_journey(journey)

      conn = post(conn, "/api/v1/journeys/#{journey.id}/archive")
      body = json_response(conn, 200)

      assert body["data"]["status"] == "archived"
    end
  end

  describe "lifecycle edge cases" do
    test "launch rejects already-active journey without new draft version",
         %{conn: conn, tenant: tenant, flow: flow} do
      insert(:flow_version, flow: flow, graph: valid_graph())
      journey = insert(:journey, tenant: tenant, flow: flow)
      {:ok, _journey} = Kalcifer.Marketing.launch_journey(journey)

      conn = post(conn, "/api/v1/journeys/#{journey.id}/launch")
      assert json_response(conn, 422) == %{"error" => "no_draft_version"}
    end

    test "pause rejects draft journey", %{conn: conn, tenant: tenant, flow: flow} do
      journey = insert(:journey, tenant: tenant, flow: flow, status: "draft")

      conn = post(conn, "/api/v1/journeys/#{journey.id}/pause")
      assert json_response(conn, 422)
    end

    test "archive rejects draft journey", %{conn: conn, tenant: tenant, flow: flow} do
      journey = insert(:journey, tenant: tenant, flow: flow, status: "draft")

      conn = post(conn, "/api/v1/journeys/#{journey.id}/archive")
      assert json_response(conn, 422)
    end

    test "delete returns 404 for other tenant's journey", %{conn: conn} do
      other_tenant = insert(:tenant)
      other_flow = insert(:flow, tenant: other_tenant)
      journey = insert(:journey, tenant: other_tenant, flow: other_flow)

      conn = delete(conn, "/api/v1/journeys/#{journey.id}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end
end
