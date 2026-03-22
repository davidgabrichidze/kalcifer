defmodule KalciferWeb.ConversationControllerTest do
  use KalciferWeb.ConnCase, async: true

  alias Kalcifer.AI.Context

  import Kalcifer.Factory

  setup do
    tenant = insert(:tenant, name: "Demo Tenant")
    %{tenant: tenant}
  end

  describe "GET /api/v1/conversations" do
    test "lists active conversations", %{conn: conn, tenant: tenant} do
      {:ok, _} = Context.create_conversation(tenant.id, %{title: "First"})
      {:ok, _} = Context.create_conversation(tenant.id, %{title: "Second"})

      conn = get(conn, "/api/v1/conversations")
      assert %{"conversations" => convs} = json_response(conn, 200)
      assert length(convs) >= 2
    end

    test "filters by kind", %{conn: conn, tenant: tenant} do
      {:ok, c1} = Context.create_conversation(tenant.id)
      {:ok, _} = Context.classify_conversation(c1, "campaign", "Camp")

      {:ok, _c2} = Context.create_conversation(tenant.id)

      conn = get(conn, "/api/v1/conversations?kind=campaign")
      assert %{"conversations" => convs} = json_response(conn, 200)
      assert Enum.all?(convs, &(&1["kind"] == "campaign"))
    end
  end

  describe "GET /api/v1/conversations/:id" do
    test "returns conversation with messages", %{conn: conn, tenant: tenant} do
      {:ok, conv} = Context.create_conversation(tenant.id, %{title: "Test"})
      {:ok, _} = Context.add_message(conv.id, "user", "Hello")
      {:ok, _} = Context.add_message(conv.id, "assistant", "Hi!")

      conn = get(conn, "/api/v1/conversations/#{conv.id}")
      body = json_response(conn, 200)
      assert body["conversation"]["title"] == "Test"
      assert length(body["messages"]) == 2
    end

    test "returns 404 for nonexistent conversation", %{conn: conn} do
      conn = get(conn, "/api/v1/conversations/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "POST /api/v1/conversations/:id/archive" do
    test "archives a conversation", %{conn: conn, tenant: tenant} do
      {:ok, conv} = Context.create_conversation(tenant.id)

      conn = post(conn, "/api/v1/conversations/#{conv.id}/archive")
      body = json_response(conn, 200)
      assert body["conversation"]["status"] == "archived"
    end
  end
end
