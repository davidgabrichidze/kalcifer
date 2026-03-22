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

  describe "PUT /api/v1/conversations/:id (rename)" do
    test "renames a conversation", %{conn: conn, tenant: tenant} do
      {:ok, conv} = Context.create_conversation(tenant.id, %{title: "Old Name"})

      conn = put(conn, "/api/v1/conversations/#{conv.id}", %{title: "New Name"})
      body = json_response(conn, 200)
      assert body["conversation"]["title"] == "New Name"
    end

    test "rejects empty title", %{conn: conn, tenant: tenant} do
      {:ok, conv} = Context.create_conversation(tenant.id)

      conn = put(conn, "/api/v1/conversations/#{conv.id}", %{title: ""})
      assert json_response(conn, 422)
    end

    test "returns 404 for nonexistent conversation", %{conn: conn} do
      conn = put(conn, "/api/v1/conversations/#{Ecto.UUID.generate()}", %{title: "X"})
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

  describe "DELETE /api/v1/conversations/:id" do
    test "deletes an unclassified conversation", %{conn: conn, tenant: tenant} do
      {:ok, conv} = Context.create_conversation(tenant.id)

      conn = delete(conn, "/api/v1/conversations/#{conv.id}")
      assert json_response(conn, 200)["ok"] == true

      # Verify it's gone
      assert Context.get_conversation(conv.id) == nil
    end

    test "rejects deletion of classified conversation", %{conn: conn, tenant: tenant} do
      {:ok, conv} = Context.create_conversation(tenant.id)
      {:ok, classified} = Context.classify_conversation(conv, "campaign", "My Campaign")

      conn = delete(conn, "/api/v1/conversations/#{classified.id}")
      body = json_response(conn, 422)
      assert body["error"] =~ "cannot be deleted"
    end

    test "returns 404 for nonexistent conversation", %{conn: conn} do
      conn = delete(conn, "/api/v1/conversations/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/v1/conversations?status=all" do
    test "returns both active and archived", %{conn: conn, tenant: tenant} do
      {:ok, _} = Context.create_conversation(tenant.id, %{title: "Active One"})
      {:ok, c2} = Context.create_conversation(tenant.id, %{title: "Archived One"})
      {:ok, _} = Context.archive_conversation(c2)

      conn = get(conn, "/api/v1/conversations?status=all")
      body = json_response(conn, 200)
      statuses = Enum.map(body["conversations"], & &1["status"]) |> Enum.uniq() |> Enum.sort()
      assert statuses == ["active", "archived"]
    end
  end
end
