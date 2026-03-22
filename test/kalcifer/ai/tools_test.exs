defmodule Kalcifer.AI.ToolsTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.AI.Tools

  import Kalcifer.Factory

  setup do
    tenant = insert(:tenant)
    %{tenant_id: tenant.id}
  end

  describe "definitions/0" do
    test "returns 12 tool definitions" do
      defs = Tools.definitions()
      assert length(defs) == 12

      names = Enum.map(defs, & &1.name)
      assert "classify_session" in names
      assert "list_flows" in names
      assert "get_flow" in names
      assert "get_flow_graph" in names
      assert "create_flow" in names
      assert "add_node" in names
      assert "modify_node" in names
      assert "list_node_types" in names
      assert "analyze_flow" in names
      assert "debug_instance" in names
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

  describe "execute/4 — classify_session" do
    test "classifies a conversation", %{tenant_id: tid} do
      {:ok, conv} = Kalcifer.AI.Context.create_conversation(tid)

      assert {:ok, json} = Tools.execute(
        "classify_session",
        %{"kind" => "campaign", "title" => "Welcome კამპანია"},
        tid,
        %{conversation_id: conv.id}
      )

      result = Jason.decode!(json)
      assert result["classified"] == true
      assert result["kind"] == "campaign"
      assert result["title"] == "Welcome კამპანია"
    end

    test "returns error without conversation_id", %{tenant_id: tid} do
      assert {:error, _} = Tools.execute(
        "classify_session",
        %{"kind" => "campaign", "title" => "Test"},
        tid,
        %{}
      )
    end

    test "rejects re-classification", %{tenant_id: tid} do
      {:ok, conv} = Kalcifer.AI.Context.create_conversation(tid)
      {:ok, _} = Kalcifer.AI.Context.classify_conversation(conv, "campaign")

      assert {:error, _} = Tools.execute(
        "classify_session",
        %{"kind" => "flow", "title" => "Changed"},
        tid,
        %{conversation_id: conv.id}
      )
    end
  end

  describe "execute/3 — get_flow_graph" do
    test "returns graph for latest version", %{tenant_id: tid} do
      tenant = Kalcifer.Repo.get!(Kalcifer.Tenants.Tenant, tid)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())

      assert {:ok, json} = Tools.execute("get_flow_graph", %{"flow_id" => flow.id}, tid)
      result = Jason.decode!(json)
      assert result["flow_id"] == flow.id
      assert result["version_number"] == 1
      assert result["node_count"] == 2
      assert length(result["nodes"]) == 2
      assert length(result["edges"]) == 1
    end

    test "returns graph for specific version number", %{tenant_id: tid} do
      tenant = Kalcifer.Repo.get!(Kalcifer.Tenants.Tenant, tid)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())

      v2_graph = %{
        "nodes" => [
          %{"id" => "n1", "type" => "event_entry", "config" => %{"event_type" => "click"}},
          %{"id" => "n2", "type" => "send_email", "config" => %{}},
          %{"id" => "n3", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"source" => "n1", "target" => "n2"},
          %{"source" => "n2", "target" => "n3"}
        ]
      }

      insert(:flow_version, flow: flow, version_number: 2, graph: v2_graph)

      assert {:ok, json} = Tools.execute("get_flow_graph", %{"flow_id" => flow.id, "version_number" => 2}, tid)
      result = Jason.decode!(json)
      assert result["version_number"] == 2
      assert result["node_count"] == 3
    end

    test "returns error for nonexistent flow", %{tenant_id: tid} do
      assert {:error, "Flow not found: " <> _} =
               Tools.execute("get_flow_graph", %{"flow_id" => Ecto.UUID.generate()}, tid)
    end
  end

  describe "execute/3 — add_node" do
    test "adds a node to draft version", %{tenant_id: tid} do
      tenant = Kalcifer.Repo.get!(Kalcifer.Tenants.Tenant, tid)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node" => %{"id" => "email_1", "type" => "send_email", "config" => %{"template_id" => "welcome"}},
        "edges" => [%{"source" => "entry_1", "target" => "email_1"}]
      }

      assert {:ok, json} = Tools.execute("add_node", input, tid)
      result = Jason.decode!(json)
      assert result["added_node"] == "email_1"
      assert result["added_edges"] == 1
      assert result["total_nodes"] == 3
    end

    test "rejects duplicate node ID", %{tenant_id: tid} do
      tenant = Kalcifer.Repo.get!(Kalcifer.Tenants.Tenant, tid)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node" => %{"id" => "entry_1", "type" => "send_email"}
      }

      assert {:error, "Node with id 'entry_1' already exists"} =
               Tools.execute("add_node", input, tid)
    end

    test "creates draft version from published when none exists", %{tenant_id: tid} do
      tenant = Kalcifer.Repo.get!(Kalcifer.Tenants.Tenant, tid)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "published", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node" => %{"id" => "wait_1", "type" => "wait", "config" => %{"duration" => "1h"}}
      }

      assert {:ok, json} = Tools.execute("add_node", input, tid)
      result = Jason.decode!(json)
      assert result["version_number"] == 2
      assert result["total_nodes"] == 3
    end

    test "returns error for nonexistent flow", %{tenant_id: tid} do
      input = %{
        "flow_id" => Ecto.UUID.generate(),
        "node" => %{"id" => "n1", "type" => "send_email"}
      }

      assert {:error, "Flow not found: " <> _} = Tools.execute("add_node", input, tid)
    end
  end

  describe "execute/3 — modify_node" do
    test "updates node config in draft version", %{tenant_id: tid} do
      tenant = Kalcifer.Repo.get!(Kalcifer.Tenants.Tenant, tid)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node_id" => "entry_1",
        "config" => %{"event_type" => "purchase_completed"}
      }

      assert {:ok, json} = Tools.execute("modify_node", input, tid)
      result = Jason.decode!(json)
      assert result["modified_node"] == "entry_1"
      assert result["node_type"] == "event_entry"

      # Verify the config was persisted
      {:ok, graph_json} = Tools.execute("get_flow_graph", %{"flow_id" => flow.id}, tid)
      graph = Jason.decode!(graph_json)
      entry = Enum.find(graph["nodes"], &(&1["id"] == "entry_1"))
      assert entry["config"]["event_type"] == "purchase_completed"
    end

    test "returns error for nonexistent node", %{tenant_id: tid} do
      tenant = Kalcifer.Repo.get!(Kalcifer.Tenants.Tenant, tid)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node_id" => "nonexistent",
        "config" => %{"foo" => "bar"}
      }

      assert {:error, "Node 'nonexistent' not found in graph"} =
               Tools.execute("modify_node", input, tid)
    end

    test "returns error for nonexistent flow", %{tenant_id: tid} do
      input = %{
        "flow_id" => Ecto.UUID.generate(),
        "node_id" => "entry_1",
        "config" => %{"foo" => "bar"}
      }

      assert {:error, "Flow not found: " <> _} = Tools.execute("modify_node", input, tid)
    end
  end

  describe "execute/3 — analyze_flow" do
    test "returns analysis for a flow with graph", %{tenant_id: tid} do
      tenant = Kalcifer.Repo.get!(Kalcifer.Tenants.Tenant, tid)
      flow = insert(:flow, tenant: tenant, name: "Analyzed Flow")
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())

      assert {:ok, json} = Tools.execute("analyze_flow", %{"flow_id" => flow.id}, tid)
      result = Jason.decode!(json)
      assert result["flow_name"] == "Analyzed Flow"
      assert result["node_count"] == 2
      assert result["edge_count"] == 1
      assert is_map(result["categories"])
      assert is_list(result["entry_nodes"])
      assert is_list(result["end_nodes"])
      assert is_map(result["preflight"])
    end

    test "returns error for nonexistent flow", %{tenant_id: tid} do
      assert {:error, "Flow not found: " <> _} =
               Tools.execute("analyze_flow", %{"flow_id" => Ecto.UUID.generate()}, tid)
    end

    test "returns error when flow has no versions", %{tenant_id: tid} do
      tenant = Kalcifer.Repo.get!(Kalcifer.Tenants.Tenant, tid)
      flow = insert(:flow, tenant: tenant)

      assert {:error, "No versions found for this flow"} =
               Tools.execute("analyze_flow", %{"flow_id" => flow.id}, tid)
    end
  end

  describe "execute/3 — debug_instance" do
    test "returns instance debug info with steps", %{tenant_id: tid} do
      tenant = Kalcifer.Repo.get!(Kalcifer.Tenants.Tenant, tid)
      flow = insert(:flow, tenant: tenant)

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: tenant,
          status: "running",
          current_nodes: ["email_1"],
          context: %{"customer_name" => "Test"}
        )

      insert(:execution_step,
        instance: instance,
        node_id: "entry_1",
        node_type: "event_entry",
        status: "completed",
        output: %{"matched" => true}
      )

      insert(:execution_step,
        instance: instance,
        node_id: "email_1",
        node_type: "send_email",
        status: "failed",
        error: %{"message" => "Provider timeout", "code" => "timeout"}
      )

      assert {:ok, json} = Tools.execute("debug_instance", %{"instance_id" => instance.id}, tid)
      result = Jason.decode!(json)
      assert result["instance_id"] == instance.id
      assert result["status"] == "running"
      assert result["current_nodes"] == ["email_1"]
      assert result["step_count"] == 2
      assert length(result["steps"]) == 2
      assert result["context_keys"] == ["customer_name"]

      # Check failed step has error
      failed = Enum.find(result["steps"], &(&1["status"] == "failed"))
      assert failed["error"]["message"] == "Provider timeout"
    end

    test "returns error for nonexistent instance", %{tenant_id: tid} do
      assert {:error, "Instance not found: " <> _} =
               Tools.execute("debug_instance", %{"instance_id" => Ecto.UUID.generate()}, tid)
    end
  end

  describe "execute/3 — unknown tool" do
    test "returns error for unknown tool", %{tenant_id: tid} do
      assert {:error, "Unknown tool: nonexistent"} =
        Tools.execute("nonexistent", %{}, tid)
    end
  end
end
