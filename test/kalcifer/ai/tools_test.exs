defmodule Kalcifer.AI.ToolsTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.AI.Tools

  import Kalcifer.Factory

  setup do
    tenant = insert(:tenant)
    %{tenant_id: tenant.id}
  end

  describe "definitions/0" do
    test "returns 6 tool definitions" do
      defs = Tools.definitions()
      assert length(defs) == 6

      names = Enum.map(defs, & &1.name)
      assert "list_flows" in names
      assert "get_flow" in names
      assert "create_flow" in names
      assert "list_node_types" in names
      assert "remember" in names
      assert "recall" in names
    end

    test "each definition has required fields" do
      for tool <- Tools.definitions() do
        assert Map.has_key?(tool, :name)
        assert Map.has_key?(tool, :description)
        assert Map.has_key?(tool, :input_schema)
      end
    end
  end

  describe "execute/3 — list_flows" do
    test "returns empty list when no flows", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute("list_flows", %{}, tid)
      assert Jason.decode!(json) == []
    end

    test "returns flows for the tenant", %{tenant_id: tid} do
      tenant = Kalcifer.Repo.get!(Kalcifer.Tenants.Tenant, tid)
      insert(:flow, tenant: tenant, name: "My Flow")

      assert {:ok, json} = Tools.execute("list_flows", %{}, tid)
      flows = Jason.decode!(json)
      assert length(flows) >= 1
      assert Enum.any?(flows, &(&1["name"] == "My Flow"))
    end
  end

  describe "execute/3 — create_flow" do
    test "creates a flow and returns its info", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute("create_flow", %{"name" => "AI Created"}, tid)
      result = Jason.decode!(json)
      assert result["name"] == "AI Created"
      assert result["status"] == "draft"
      assert result["message"] == "Flow created successfully"
    end

    test "returns error when name missing", %{tenant_id: tid} do
      assert {:error, "Internal error executing create_flow"} =
        Tools.execute("create_flow", %{}, tid)
    end
  end

  describe "execute/3 — get_flow" do
    test "returns flow details", %{tenant_id: tid} do
      tenant = Kalcifer.Repo.get!(Kalcifer.Tenants.Tenant, tid)
      flow = insert(:flow, tenant: tenant, name: "Detail Flow")

      assert {:ok, json} = Tools.execute("get_flow", %{"flow_id" => flow.id}, tid)
      result = Jason.decode!(json)
      assert result["name"] == "Detail Flow"
    end

    test "returns error for nonexistent flow", %{tenant_id: tid} do
      assert {:error, _} = Tools.execute("get_flow", %{"flow_id" => Ecto.UUID.generate()}, tid)
    end
  end

  describe "execute/3 — list_node_types" do
    test "returns registered node types", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute("list_node_types", %{}, tid)
      nodes = Jason.decode!(json)
      assert is_list(nodes)
      # Should have at least the built-in nodes
      assert length(nodes) >= 20

      types = Enum.map(nodes, & &1["type"])
      assert "send_email" in types
      assert "condition" in types
      assert "wait" in types
    end
  end

  describe "execute/3 — remember & recall" do
    test "remember saves and recall retrieves", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute(
        "remember",
        %{"key" => "language", "value" => "Georgian", "category" => "preference"},
        tid
      )

      assert %{"remembered" => true} = Jason.decode!(json)

      assert {:ok, recall_json} = Tools.execute("recall", %{"key" => "language"}, tid)
      result = Jason.decode!(recall_json)
      assert result["found"] == true
      assert result["value"] == "Georgian"
      assert result["category"] == "preference"
    end

    test "recall returns not found for missing key", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute("recall", %{"key" => "nonexistent"}, tid)
      result = Jason.decode!(json)
      assert result["found"] == false
    end

    test "recall all returns all memories", %{tenant_id: tid} do
      Tools.execute("remember", %{"key" => "k1", "value" => "v1"}, tid)
      Tools.execute("remember", %{"key" => "k2", "value" => "v2"}, tid)

      assert {:ok, json} = Tools.execute("recall", %{}, tid)
      memories = Jason.decode!(json)
      assert length(memories) >= 2
    end
  end

  describe "execute/3 — unknown tool" do
    test "returns error for unknown tool", %{tenant_id: tid} do
      assert {:error, "Unknown tool: nonexistent"} =
        Tools.execute("nonexistent", %{}, tid)
    end
  end
end
