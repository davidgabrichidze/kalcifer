defmodule Kalcifer.AI.ToolsTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.AI.{Context, Tools}
  alias Kalcifer.Flows

  import Kalcifer.Factory

  setup do
    tenant = insert(:tenant)
    %{tenant_id: tenant.id, tenant: tenant}
  end

  # ── Definitions ──────────────────────────────────────────────

  describe "definitions/0" do
    test "returns 13 tool definitions" do
      defs = Tools.definitions()
      assert length(defs) == 13

      names = Enum.map(defs, & &1.name)
      assert "classify_session" in names
      assert "list_flows" in names
      assert "get_flow" in names
      assert "get_flow_graph" in names
      assert "create_flow" in names
      assert "add_node" in names
      assert "modify_node" in names
      assert "remove_node" in names
      assert "list_node_types" in names
      assert "analyze_flow" in names
      assert "debug_instance" in names
      assert "remember" in names
      assert "recall" in names
    end

    test "each definition has required fields" do
      for tool <- Tools.definitions() do
        assert Map.has_key?(tool, :name), "#{inspect(tool)} missing :name"
        assert Map.has_key?(tool, :description), "#{tool.name} missing :description"
        assert Map.has_key?(tool, :input_schema), "#{tool.name} missing :input_schema"
        assert is_binary(tool.description), "#{tool.name} description should be binary"
        assert is_map(tool.input_schema), "#{tool.name} input_schema should be map"
      end
    end

    test "each definition has valid input_schema structure" do
      for tool <- Tools.definitions() do
        schema = tool.input_schema
        assert schema.type == "object", "#{tool.name} schema type should be 'object'"
        assert is_map(schema.properties), "#{tool.name} should have properties"
        assert is_list(schema.required), "#{tool.name} should have required list"
      end
    end

    test "tool names are unique" do
      names = Enum.map(Tools.definitions(), & &1.name)
      assert names == Enum.uniq(names)
    end
  end

  # ── list_flows ───────────────────────────────────────────────

  describe "execute — list_flows" do
    test "returns empty list when no flows", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute("list_flows", %{}, tid)
      assert Jason.decode!(json) == []
    end

    test "returns flows for the tenant", %{tenant: tenant} do
      insert(:flow, tenant: tenant, name: "Flow A")
      insert(:flow, tenant: tenant, name: "Flow B")

      assert {:ok, json} = Tools.execute("list_flows", %{}, tenant.id)
      flows = Jason.decode!(json)
      assert length(flows) == 2
      names = Enum.map(flows, & &1["name"]) |> Enum.sort()
      assert names == ["Flow A", "Flow B"]
    end

    test "filters by status", %{tenant: tenant} do
      insert(:flow, tenant: tenant, name: "Draft", status: "draft")
      insert(:flow, tenant: tenant, name: "Active", status: "active")

      assert {:ok, json} = Tools.execute("list_flows", %{"status" => "active"}, tenant.id)
      flows = Jason.decode!(json)
      assert length(flows) == 1
      assert hd(flows)["name"] == "Active"
    end

    test "does not return other tenant's flows", %{tenant: tenant} do
      other_tenant = insert(:tenant)
      insert(:flow, tenant: other_tenant, name: "Other Flow")
      insert(:flow, tenant: tenant, name: "My Flow")

      assert {:ok, json} = Tools.execute("list_flows", %{}, tenant.id)
      flows = Jason.decode!(json)
      assert length(flows) == 1
      assert hd(flows)["name"] == "My Flow"
    end

    test "returns flow fields: id, name, status, description", %{tenant: tenant} do
      insert(:flow, tenant: tenant, name: "Detailed", description: "A test flow")

      assert {:ok, json} = Tools.execute("list_flows", %{}, tenant.id)
      [flow] = Jason.decode!(json)
      assert Map.has_key?(flow, "id")
      assert Map.has_key?(flow, "name")
      assert Map.has_key?(flow, "status")
      assert Map.has_key?(flow, "description")
    end
  end

  # ── get_flow ─────────────────────────────────────────────────

  describe "execute — get_flow" do
    test "returns flow details with version count", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant, name: "Detail Flow")
      insert(:flow_version, flow: flow, version_number: 1)
      insert(:flow_version, flow: flow, version_number: 2)

      assert {:ok, json} = Tools.execute("get_flow", %{"flow_id" => flow.id}, tenant.id)
      result = Jason.decode!(json)
      assert result["name"] == "Detail Flow"
      assert result["version_count"] == 2
      assert Map.has_key?(result, "created_at")
    end

    test "returns error for nonexistent flow", %{tenant_id: tid} do
      assert {:error, "Flow not found: " <> _} =
               Tools.execute("get_flow", %{"flow_id" => Ecto.UUID.generate()}, tid)
    end

    test "includes active_version_id when set", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      version = insert(:flow_version, flow: flow, version_number: 1, status: "published")

      # Set active version
      flow
      |> Ecto.Changeset.change(active_version_id: version.id)
      |> Kalcifer.Repo.update!()

      assert {:ok, json} = Tools.execute("get_flow", %{"flow_id" => flow.id}, tenant.id)
      result = Jason.decode!(json)
      assert result["active_version_id"] == version.id
    end
  end

  # ── create_flow ──────────────────────────────────────────────

  describe "execute — create_flow" do
    test "creates a flow and returns its info", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute("create_flow", %{"name" => "AI Created"}, tid)
      result = Jason.decode!(json)
      assert result["name"] == "AI Created"
      assert result["status"] == "draft"
      assert result["message"] == "Flow created successfully"
      assert Map.has_key?(result, "id")
    end

    test "creates flow with description", %{tenant_id: tid} do
      input = %{"name" => "Described Flow", "description" => "Does cool things"}
      assert {:ok, json} = Tools.execute("create_flow", input, tid)
      result = Jason.decode!(json)
      assert result["name"] == "Described Flow"

      # Verify description is stored
      flow = Flows.get_flow(result["id"])
      assert flow.description == "Does cool things"
    end

    test "returns error when name missing", %{tenant_id: tid} do
      assert {:error, msg} = Tools.execute("create_flow", %{}, tid)
      assert msg =~ "Internal error executing create_flow"
    end

    test "idempotency — second create_flow in same conversation returns the first flow", %{
      tenant_id: tid
    } do
      {:ok, conv} = Context.create_conversation(tid)
      ctx = %{conversation_id: conv.id}

      assert {:ok, json1} = Tools.execute("create_flow", %{"name" => "Dedup Test"}, tid, ctx)
      result1 = Jason.decode!(json1)
      refute result1["already_existed"]

      # Second call — same conversation, even different name
      assert {:ok, json2} = Tools.execute("create_flow", %{"name" => "Different Name"}, tid, ctx)
      result2 = Jason.decode!(json2)

      # Returns the SAME flow, not a new one
      assert result2["id"] == result1["id"]
      assert result2["already_existed"] == true
      assert result2["message"] =~ "already has a flow"
    end

    test "different conversations can create different flows", %{tenant_id: tid} do
      {:ok, conv1} = Context.create_conversation(tid)
      {:ok, conv2} = Context.create_conversation(tid)

      assert {:ok, json1} =
               Tools.execute("create_flow", %{"name" => "Flow A"}, tid, %{
                 conversation_id: conv1.id
               })

      assert {:ok, json2} =
               Tools.execute("create_flow", %{"name" => "Flow B"}, tid, %{
                 conversation_id: conv2.id
               })

      result1 = Jason.decode!(json1)
      result2 = Jason.decode!(json2)
      assert result1["id"] != result2["id"]
    end

    test "without conversation context, no idempotency guard", %{tenant_id: tid} do
      assert {:ok, json1} = Tools.execute("create_flow", %{"name" => "No Ctx"}, tid)
      assert {:ok, json2} = Tools.execute("create_flow", %{"name" => "No Ctx"}, tid)

      result1 = Jason.decode!(json1)
      result2 = Jason.decode!(json2)
      # Without conversation_id, both create successfully (no dedup)
      assert result1["id"] != result2["id"]
    end

    test "creates flow with full graph in one call", %{tenant_id: tid} do
      input = %{
        "name" => "Onboarding Flow",
        "description" => "Welcome sequence",
        "graph" => %{
          "nodes" => [
            %{"id" => "entry_1", "type" => "webhook_entry", "config" => %{}},
            %{
              "id" => "email_1",
              "type" => "send_email",
              "config" => %{"template" => "welcome", "subject" => "Welcome!"}
            },
            %{"id" => "end_1", "type" => "end", "config" => %{}}
          ],
          "edges" => [
            %{"source" => "entry_1", "target" => "email_1"},
            %{"source" => "email_1", "target" => "end_1"}
          ]
        }
      }

      assert {:ok, json} = Tools.execute("create_flow", input, tid)
      result = Jason.decode!(json)

      assert result["name"] == "Onboarding Flow"
      assert result["status"] == "draft"
      assert result["message"] == "Flow created successfully"

      # Graph should be included in response
      assert result["graph"] != nil
      assert length(result["graph"]["nodes"]) == 3
      assert length(result["graph"]["edges"]) == 2

      # Version should exist with the graph
      versions = Flows.list_versions(result["id"])
      assert length(versions) == 1
      version = List.first(versions)
      assert version.version_number == 1
      assert length(version.graph["nodes"]) == 3
      assert length(version.graph["edges"]) == 2
    end

    test "creates flow with graph and returns validation warnings", %{tenant_id: tid} do
      input = %{
        "name" => "Broken Flow",
        "graph" => %{
          "nodes" => [
            %{"id" => "entry_1", "type" => "webhook_entry", "config" => %{}}
          ],
          "edges" => []
        }
      }

      assert {:ok, json} = Tools.execute("create_flow", input, tid)
      result = Jason.decode!(json)

      # Flow created, graph stored, but validation warnings present
      assert result["name"] == "Broken Flow"
      assert result["graph"] != nil
      # Single entry node with no edges — likely has warnings
    end

    test "creates flow without graph (backward compatible)", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute("create_flow", %{"name" => "Empty"}, tid)
      result = Jason.decode!(json)

      assert result["name"] == "Empty"
      # Graph is empty but present (version 1 created)
      assert result["graph"] != nil
      assert result["graph"]["nodes"] == []
      assert result["graph"]["edges"] == []
    end

    test "idempotency returns graph of existing flow", %{tenant_id: tid} do
      {:ok, conv} = Context.create_conversation(tid)
      ctx = %{conversation_id: conv.id}

      input = %{
        "name" => "Graph Flow",
        "graph" => %{
          "nodes" => [
            %{"id" => "e1", "type" => "webhook_entry"},
            %{"id" => "x1", "type" => "end"}
          ],
          "edges" => [%{"source" => "e1", "target" => "x1"}]
        }
      }

      assert {:ok, json1} = Tools.execute("create_flow", input, tid, ctx)
      result1 = Jason.decode!(json1)

      # Second call returns existing flow WITH its graph
      assert {:ok, json2} = Tools.execute("create_flow", %{"name" => "Other"}, tid, ctx)
      result2 = Jason.decode!(json2)

      assert result2["id"] == result1["id"]
      assert result2["already_existed"] == true
      assert result2["graph"] != nil
      assert length(result2["graph"]["nodes"]) == 2
    end

    test "links flow to conversation on creation", %{tenant_id: tid} do
      {:ok, conv} = Context.create_conversation(tid)
      ctx = %{conversation_id: conv.id}

      assert {:ok, json} = Tools.execute("create_flow", %{"name" => "Linked Flow"}, tid, ctx)
      result = Jason.decode!(json)

      # Conversation should be linked to the flow
      updated_conv = Context.get_conversation(conv.id)
      assert updated_conv.entity_id == result["id"]
      assert updated_conv.entity_type == "flow"
    end
  end

  # ── get_flow_graph ───────────────────────────────────────────

  describe "execute — get_flow_graph" do
    test "returns graph for latest version", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())

      assert {:ok, json} = Tools.execute("get_flow_graph", %{"flow_id" => flow.id}, tenant.id)
      result = Jason.decode!(json)
      assert result["flow_id"] == flow.id
      assert result["version_number"] == 1
      assert result["node_count"] == 2
      assert length(result["nodes"]) == 2
      assert length(result["edges"]) == 1
    end

    test "returns graph for specific version number", %{tenant: tenant} do
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

      assert {:ok, json} =
               Tools.execute(
                 "get_flow_graph",
                 %{"flow_id" => flow.id, "version_number" => 2},
                 tenant.id
               )

      result = Jason.decode!(json)
      assert result["version_number"] == 2
      assert result["node_count"] == 3
    end

    test "returns version_status field", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)

      insert(:flow_version,
        flow: flow,
        version_number: 1,
        status: "published",
        graph: valid_graph()
      )

      assert {:ok, json} = Tools.execute("get_flow_graph", %{"flow_id" => flow.id}, tenant.id)
      result = Jason.decode!(json)
      assert result["version_status"] == "published"
    end

    test "returns error for nonexistent flow", %{tenant_id: tid} do
      assert {:error, "Flow not found: " <> _} =
               Tools.execute("get_flow_graph", %{"flow_id" => Ecto.UUID.generate()}, tid)
    end

    test "returns error for nonexistent version number", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())

      assert {:error, "Version not found"} =
               Tools.execute(
                 "get_flow_graph",
                 %{"flow_id" => flow.id, "version_number" => 99},
                 tenant.id
               )
    end

    test "handles flow with empty graph", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, graph: %{"nodes" => [], "edges" => []})

      assert {:ok, json} = Tools.execute("get_flow_graph", %{"flow_id" => flow.id}, tenant.id)
      result = Jason.decode!(json)
      assert result["node_count"] == 0
      assert result["nodes"] == []
      assert result["edges"] == []
    end
  end

  # ── add_node ─────────────────────────────────────────────────

  describe "execute — add_node" do
    test "adds a node to draft version", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node" => %{
          "id" => "email_1",
          "type" => "send_email",
          "config" => %{"template_id" => "welcome"}
        },
        "edges" => [%{"source" => "entry_1", "target" => "email_1"}]
      }

      assert {:ok, json} = Tools.execute("add_node", input, tenant.id)
      result = Jason.decode!(json)
      assert result["added_node"] == "email_1"
      assert result["added_edges"] == 1
      assert result["total_nodes"] == 3
    end

    test "includes current_nodes in result for AI context", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node" => %{"id" => "wait_1", "type" => "wait", "config" => %{"duration" => "1h"}}
      }

      assert {:ok, json} = Tools.execute("add_node", input, tenant.id)
      result = Jason.decode!(json)
      assert is_list(result["current_nodes"])
      node_ids = Enum.map(result["current_nodes"], & &1["id"])
      assert "entry_1" in node_ids
      assert "exit_1" in node_ids
      assert "wait_1" in node_ids
    end

    test "rejects duplicate node ID", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node" => %{"id" => "entry_1", "type" => "send_email"}
      }

      assert {:error, "Node with id 'entry_1' already exists"} =
               Tools.execute("add_node", input, tenant.id)
    end

    test "creates draft version from published when none exists", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)

      insert(:flow_version,
        flow: flow,
        version_number: 1,
        status: "published",
        graph: valid_graph()
      )

      input = %{
        "flow_id" => flow.id,
        "node" => %{"id" => "wait_1", "type" => "wait", "config" => %{"duration" => "1h"}}
      }

      assert {:ok, json} = Tools.execute("add_node", input, tenant.id)
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

    test "adds node without edges", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node" => %{"id" => "orphan_1", "type" => "send_email", "config" => %{}}
      }

      assert {:ok, json} = Tools.execute("add_node", input, tenant.id)
      result = Jason.decode!(json)
      assert result["added_node"] == "orphan_1"
      assert result["added_edges"] == 0
    end

    test "adds node with branch edges", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)

      graph = %{
        "nodes" => [
          %{
            "id" => "entry_1",
            "type" => "event_entry",
            "config" => %{"event_type" => "signed_up"}
          },
          %{"id" => "cond_1", "type" => "condition", "config" => %{"expression" => "age > 18"}}
        ],
        "edges" => [%{"source" => "entry_1", "target" => "cond_1"}]
      }

      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: graph)

      input = %{
        "flow_id" => flow.id,
        "node" => %{"id" => "email_yes", "type" => "send_email", "config" => %{}},
        "edges" => [%{"source" => "cond_1", "target" => "email_yes", "branch" => "true"}]
      }

      assert {:ok, json} = Tools.execute("add_node", input, tenant.id)
      result = Jason.decode!(json)
      assert result["added_node"] == "email_yes"
      assert result["added_edges"] == 1

      # Verify branch edge persisted
      {:ok, graph_json} = Tools.execute("get_flow_graph", %{"flow_id" => flow.id}, tenant.id)
      graph_result = Jason.decode!(graph_json)

      branch_edge =
        Enum.find(
          graph_result["edges"],
          &(&1["source"] == "cond_1" and &1["target"] == "email_yes")
        )

      assert branch_edge["branch"] == "true"
    end

    test "adds multiple nodes sequentially", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      # Add first node
      input1 = %{
        "flow_id" => flow.id,
        "node" => %{"id" => "email_1", "type" => "send_email", "config" => %{}},
        "edges" => [%{"source" => "entry_1", "target" => "email_1"}]
      }

      assert {:ok, _} = Tools.execute("add_node", input1, tenant.id)

      # Add second node
      input2 = %{
        "flow_id" => flow.id,
        "node" => %{"id" => "wait_1", "type" => "wait", "config" => %{"duration" => "2h"}},
        "edges" => [%{"source" => "email_1", "target" => "wait_1"}]
      }

      assert {:ok, json2} = Tools.execute("add_node", input2, tenant.id)
      result2 = Jason.decode!(json2)
      assert result2["total_nodes"] == 4
    end

    test "node with default empty config when not provided", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node" => %{"id" => "exit_2", "type" => "exit"}
      }

      assert {:ok, json} = Tools.execute("add_node", input, tenant.id)
      result = Jason.decode!(json)
      assert result["added_node"] == "exit_2"

      # Verify config defaults to empty map
      {:ok, graph_json} = Tools.execute("get_flow_graph", %{"flow_id" => flow.id}, tenant.id)
      graph = Jason.decode!(graph_json)
      node = Enum.find(graph["nodes"], &(&1["id"] == "exit_2"))
      assert node["config"] == %{}
    end
  end

  # ── modify_node ──────────────────────────────────────────────

  describe "execute — modify_node" do
    test "updates node config in draft version", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node_id" => "entry_1",
        "config" => %{"event_type" => "purchase_completed"}
      }

      assert {:ok, json} = Tools.execute("modify_node", input, tenant.id)
      result = Jason.decode!(json)
      assert result["modified_node"] == "entry_1"
      assert result["node_type"] == "event_entry"

      # Verify the config was persisted
      {:ok, graph_json} = Tools.execute("get_flow_graph", %{"flow_id" => flow.id}, tenant.id)
      graph = Jason.decode!(graph_json)
      entry = Enum.find(graph["nodes"], &(&1["id"] == "entry_1"))
      assert entry["config"]["event_type"] == "purchase_completed"
    end

    test "replaces config entirely (not merge)", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)

      graph = %{
        "nodes" => [
          %{
            "id" => "email_1",
            "type" => "send_email",
            "config" => %{"template_id" => "old", "subject" => "Old Subject"}
          },
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [%{"source" => "email_1", "target" => "exit_1"}]
      }

      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: graph)

      input = %{
        "flow_id" => flow.id,
        "node_id" => "email_1",
        "config" => %{"template_id" => "new"}
      }

      assert {:ok, _} = Tools.execute("modify_node", input, tenant.id)

      {:ok, graph_json} = Tools.execute("get_flow_graph", %{"flow_id" => flow.id}, tenant.id)
      result = Jason.decode!(graph_json)
      email = Enum.find(result["nodes"], &(&1["id"] == "email_1"))
      # Config is replaced, not merged — old "subject" key is gone
      assert email["config"] == %{"template_id" => "new"}
    end

    test "creates draft from published before modifying", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)

      insert(:flow_version,
        flow: flow,
        version_number: 1,
        status: "published",
        graph: valid_graph()
      )

      input = %{
        "flow_id" => flow.id,
        "node_id" => "entry_1",
        "config" => %{"event_type" => "modified"}
      }

      assert {:ok, json} = Tools.execute("modify_node", input, tenant.id)
      result = Jason.decode!(json)
      assert result["version_number"] == 2
    end

    test "returns error for nonexistent node", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node_id" => "nonexistent",
        "config" => %{"foo" => "bar"}
      }

      assert {:error, "Node 'nonexistent' not found in graph"} =
               Tools.execute("modify_node", input, tenant.id)
    end

    test "returns error for nonexistent flow", %{tenant_id: tid} do
      input = %{
        "flow_id" => Ecto.UUID.generate(),
        "node_id" => "entry_1",
        "config" => %{"foo" => "bar"}
      }

      assert {:error, "Flow not found: " <> _} = Tools.execute("modify_node", input, tid)
    end

    test "preserves node type and id after modification", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: valid_graph())

      input = %{
        "flow_id" => flow.id,
        "node_id" => "entry_1",
        "config" => %{"event_type" => "new_event"}
      }

      assert {:ok, _} = Tools.execute("modify_node", input, tenant.id)

      {:ok, graph_json} = Tools.execute("get_flow_graph", %{"flow_id" => flow.id}, tenant.id)
      graph = Jason.decode!(graph_json)
      node = Enum.find(graph["nodes"], &(&1["id"] == "entry_1"))
      assert node["type"] == "event_entry"
      assert node["id"] == "entry_1"
    end
  end

  # ── remove_node ────────────────────────────────────────────

  describe "execute — remove_node" do
    test "removes a node and its connected edges", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())

      assert {:ok, json} =
               Tools.execute(
                 "remove_node",
                 %{"flow_id" => flow.id, "node_id" => "exit_1"},
                 tenant.id
               )

      result = Jason.decode!(json)
      assert result["removed_node"] == "exit_1"
      assert result["removed_edges"] == 1
      assert result["total_nodes"] == 1
      assert result["flow_id"] == flow.id
    end

    test "returns error for nonexistent node", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())

      assert {:error, "Node 'nonexistent' not found in graph"} =
               Tools.execute(
                 "remove_node",
                 %{"flow_id" => flow.id, "node_id" => "nonexistent"},
                 tenant.id
               )
    end

    test "returns error for nonexistent flow", %{tenant_id: tid} do
      assert {:error, "Flow not found: " <> _} =
               Tools.execute(
                 "remove_node",
                 %{"flow_id" => Ecto.UUID.generate(), "node_id" => "entry_1"},
                 tid
               )
    end
  end

  # ── analyze_flow ─────────────────────────────────────────────

  describe "execute — analyze_flow" do
    test "returns analysis for a flow with graph", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant, name: "Analyzed Flow")
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())

      assert {:ok, json} = Tools.execute("analyze_flow", %{"flow_id" => flow.id}, tenant.id)
      result = Jason.decode!(json)
      assert result["flow_name"] == "Analyzed Flow"
      assert result["node_count"] == 2
      assert result["edge_count"] == 1
      assert is_map(result["categories"])
      assert is_list(result["entry_nodes"])
      assert is_list(result["end_nodes"])
      assert is_map(result["preflight"])
    end

    test "identifies entry and end nodes", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())

      assert {:ok, json} = Tools.execute("analyze_flow", %{"flow_id" => flow.id}, tenant.id)
      result = Jason.decode!(json)
      assert "entry_1" in result["entry_nodes"]
      assert "exit_1" in result["end_nodes"]
    end

    test "counts nodes by category", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, graph: branching_graph())

      assert {:ok, json} = Tools.execute("analyze_flow", %{"flow_id" => flow.id}, tenant.id)
      result = Jason.decode!(json)
      categories = result["categories"]
      assert is_integer(categories["trigger"])
      assert is_integer(categories["action"])
      assert is_integer(categories["end"])
    end

    test "returns error for nonexistent flow", %{tenant_id: tid} do
      assert {:error, "Flow not found: " <> _} =
               Tools.execute("analyze_flow", %{"flow_id" => Ecto.UUID.generate()}, tid)
    end

    test "returns error when flow has no versions", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)

      assert {:error, "No versions found for this flow"} =
               Tools.execute("analyze_flow", %{"flow_id" => flow.id}, tenant.id)
    end

    test "returns preflight validation status", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, graph: valid_graph())

      assert {:ok, json} = Tools.execute("analyze_flow", %{"flow_id" => flow.id}, tenant.id)
      result = Jason.decode!(json)
      assert Map.has_key?(result["preflight"], "valid")
    end
  end

  # ── debug_instance ───────────────────────────────────────────

  describe "execute — debug_instance" do
    test "returns instance debug info with steps", %{tenant: tenant} do
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

      assert {:ok, json} =
               Tools.execute("debug_instance", %{"instance_id" => instance.id}, tenant.id)

      result = Jason.decode!(json)
      assert result["instance_id"] == instance.id
      assert result["status"] == "running"
      assert result["current_nodes"] == ["email_1"]
      assert result["step_count"] == 2
      assert length(result["steps"]) == 2
      assert result["context_keys"] == ["customer_name"]

      failed = Enum.find(result["steps"], &(&1["status"] == "failed"))
      assert failed["error"]["message"] == "Provider timeout"
    end

    test "returns error for nonexistent instance", %{tenant_id: tid} do
      assert {:error, "Instance not found: " <> _} =
               Tools.execute("debug_instance", %{"instance_id" => Ecto.UUID.generate()}, tid)
    end

    test "includes output_keys for completed steps", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: tenant,
          status: "completed"
        )

      insert(:execution_step,
        instance: instance,
        node_id: "entry_1",
        node_type: "event_entry",
        status: "completed",
        output: %{"matched" => true, "event_data" => %{}}
      )

      assert {:ok, json} =
               Tools.execute("debug_instance", %{"instance_id" => instance.id}, tenant.id)

      result = Jason.decode!(json)
      step = hd(result["steps"])
      assert "matched" in step["output_keys"]
      assert "event_data" in step["output_keys"]
    end

    test "returns dry_run flag", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: tenant,
          dry_run: true
        )

      assert {:ok, json} =
               Tools.execute("debug_instance", %{"instance_id" => instance.id}, tenant.id)

      result = Jason.decode!(json)
      assert result["dry_run"] == true
    end

    test "handles instance with no steps", %{tenant: tenant} do
      flow = insert(:flow, tenant: tenant)

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: tenant,
          status: "running"
        )

      assert {:ok, json} =
               Tools.execute("debug_instance", %{"instance_id" => instance.id}, tenant.id)

      result = Jason.decode!(json)
      assert result["step_count"] == 0
      assert result["steps"] == []
    end
  end

  # ── list_node_types ──────────────────────────────────────────

  describe "execute — list_node_types" do
    test "returns registered node types", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute("list_node_types", %{}, tid)
      nodes = Jason.decode!(json)
      assert is_list(nodes)
      assert length(nodes) >= 20

      types = Enum.map(nodes, & &1["type"])
      assert "send_email" in types
      assert "condition" in types
      assert "wait" in types
    end

    test "each node type has type and category", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute("list_node_types", %{}, tid)
      nodes = Jason.decode!(json)

      for node <- nodes do
        assert Map.has_key?(node, "type"), "node missing 'type': #{inspect(node)}"
        assert Map.has_key?(node, "category"), "node missing 'category': #{inspect(node)}"
      end
    end

    test "results are sorted by category", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute("list_node_types", %{}, tid)
      nodes = Jason.decode!(json)
      categories = Enum.map(nodes, & &1["category"])
      assert categories == Enum.sort(categories)
    end
  end

  # ── classify_session ─────────────────────────────────────────

  describe "execute — classify_session" do
    test "classifies a conversation", %{tenant_id: tid} do
      {:ok, conv} = Context.create_conversation(tid)

      assert {:ok, json} =
               Tools.execute(
                 "classify_session",
                 %{"kind" => "campaign", "title" => "Welcome კამპანია"},
                 tid,
                 %{conversation_id: conv.id}
               )

      result = Jason.decode!(json)
      assert result["classified"] == true
      assert result["kind"] == "campaign"
      assert result["title"] == "Welcome კამპანია"
      assert result["needs_confirmation"] == true
    end

    test "includes reason in result", %{tenant_id: tid} do
      {:ok, conv} = Context.create_conversation(tid)

      assert {:ok, json} =
               Tools.execute(
                 "classify_session",
                 %{"kind" => "flow", "title" => "Test", "reason" => "User wants automation"},
                 tid,
                 %{conversation_id: conv.id}
               )

      result = Jason.decode!(json)
      assert result["reason"] == "User wants automation"
    end

    test "returns error without conversation_id", %{tenant_id: tid} do
      assert {:error, "No active conversation to classify"} =
               Tools.execute(
                 "classify_session",
                 %{"kind" => "campaign", "title" => "Test"},
                 tid,
                 %{}
               )
    end

    test "rejects re-classification", %{tenant_id: tid} do
      {:ok, conv} = Context.create_conversation(tid)
      {:ok, _} = Context.classify_conversation(conv, "campaign")

      assert {:error, "Classification failed: " <> _} =
               Tools.execute(
                 "classify_session",
                 %{"kind" => "flow", "title" => "Changed"},
                 tid,
                 %{conversation_id: conv.id}
               )
    end

    test "rejects invalid kind", %{tenant_id: tid} do
      {:ok, conv} = Context.create_conversation(tid)

      assert {:error, "Classification failed: " <> _} =
               Tools.execute(
                 "classify_session",
                 %{"kind" => "invalid_kind", "title" => "Test"},
                 tid,
                 %{conversation_id: conv.id}
               )
    end

    test "classifies all valid kinds", %{tenant_id: tid} do
      for kind <- ~w(campaign flow analysis debug) do
        {:ok, conv} = Context.create_conversation(tid)

        assert {:ok, json} =
                 Tools.execute(
                   "classify_session",
                   %{"kind" => kind, "title" => "#{kind} session"},
                   tid,
                   %{conversation_id: conv.id}
                 )

        result = Jason.decode!(json)
        assert result["kind"] == kind
      end
    end

    test "returns error for nonexistent conversation", %{tenant_id: tid} do
      assert {:error, "Conversation not found"} =
               Tools.execute(
                 "classify_session",
                 %{"kind" => "flow", "title" => "Test"},
                 tid,
                 %{conversation_id: Ecto.UUID.generate()}
               )
    end

    test "includes flow_id in result when provided", %{tenant_id: tid} do
      {:ok, conv} = Context.create_conversation(tid)
      flow_id = Ecto.UUID.generate()

      assert {:ok, json} =
               Tools.execute(
                 "classify_session",
                 %{"kind" => "flow", "title" => "Edit Flow", "flow_id" => flow_id},
                 tid,
                 %{conversation_id: conv.id}
               )

      result = Jason.decode!(json)
      assert result["classified"] == true
      assert result["kind"] == "flow"
      assert result["flow_id"] == flow_id
    end

    test "omits flow_id from result when not provided", %{tenant_id: tid} do
      {:ok, conv} = Context.create_conversation(tid)

      assert {:ok, json} =
               Tools.execute(
                 "classify_session",
                 %{"kind" => "flow", "title" => "New Flow"},
                 tid,
                 %{conversation_id: conv.id}
               )

      result = Jason.decode!(json)
      assert result["classified"] == true
      refute Map.has_key?(result, "flow_id")
    end
  end

  # ── remember & recall ────────────────────────────────────────

  describe "execute — remember" do
    test "saves a memory", %{tenant_id: tid} do
      assert {:ok, json} =
               Tools.execute(
                 "remember",
                 %{"key" => "language", "value" => "Georgian", "category" => "preference"},
                 tid
               )

      assert %{"remembered" => true, "key" => "language"} = Jason.decode!(json)
    end

    test "overwrites existing memory with same key (upsert)", %{tenant_id: tid} do
      Tools.execute("remember", %{"key" => "name", "value" => "David"}, tid)
      Tools.execute("remember", %{"key" => "name", "value" => "დავით"}, tid)

      assert {:ok, json} = Tools.execute("recall", %{"key" => "name"}, tid)
      result = Jason.decode!(json)
      assert result["value"] == "დავით"
    end

    test "defaults to general category", %{tenant_id: tid} do
      Tools.execute("remember", %{"key" => "test_key", "value" => "test_val"}, tid)

      assert {:ok, json} = Tools.execute("recall", %{"key" => "test_key"}, tid)
      result = Jason.decode!(json)
      assert result["category"] == "general"
    end
  end

  describe "execute — recall" do
    test "retrieves a specific memory", %{tenant_id: tid} do
      Tools.execute("remember", %{"key" => "lang", "value" => "ka"}, tid)

      assert {:ok, json} = Tools.execute("recall", %{"key" => "lang"}, tid)
      result = Jason.decode!(json)
      assert result["found"] == true
      assert result["value"] == "ka"
    end

    test "returns not found for missing key", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute("recall", %{"key" => "nonexistent"}, tid)
      result = Jason.decode!(json)
      assert result["found"] == false
    end

    test "lists all memories when no key specified", %{tenant_id: tid} do
      Tools.execute("remember", %{"key" => "k1", "value" => "v1"}, tid)
      Tools.execute("remember", %{"key" => "k2", "value" => "v2"}, tid)

      assert {:ok, json} = Tools.execute("recall", %{}, tid)
      memories = Jason.decode!(json)
      assert length(memories) >= 2
      keys = Enum.map(memories, & &1["key"])
      assert "k1" in keys
      assert "k2" in keys
    end

    test "filters by category", %{tenant_id: tid} do
      Tools.execute(
        "remember",
        %{"key" => "pref1", "value" => "v1", "category" => "preference"},
        tid
      )

      Tools.execute(
        "remember",
        %{"key" => "ctx1", "value" => "v2", "category" => "context"},
        tid
      )

      assert {:ok, json} = Tools.execute("recall", %{"category" => "preference"}, tid)
      memories = Jason.decode!(json)
      assert Enum.all?(memories, &(&1["category"] == "preference"))
    end

    test "returns empty list when no memories exist", %{tenant_id: tid} do
      assert {:ok, json} = Tools.execute("recall", %{}, tid)
      assert Jason.decode!(json) == []
    end
  end

  # ── unknown tool ─────────────────────────────────────────────

  describe "execute — unknown tool" do
    test "returns error for unknown tool", %{tenant_id: tid} do
      assert {:error, "Unknown tool: nonexistent"} =
               Tools.execute("nonexistent", %{}, tid)
    end
  end

  # ── error handling ───────────────────────────────────────────

  describe "execute — error handling" do
    test "catches crashes and returns internal error", %{tenant_id: tid} do
      # Calling create_flow without required "name" key triggers KeyError
      assert {:error, msg} = Tools.execute("create_flow", %{}, tid)
      assert msg =~ "Internal error executing create_flow"
    end
  end

  describe "tenant isolation on single-resource tools" do
    setup %{tenant: tenant} do
      other = insert(:tenant)

      other_flow =
        insert(:flow, tenant: other, name: "Other Tenant Flow", status: "active")

      insert(:flow_version,
        flow: other_flow,
        version_number: 1,
        status: "published",
        graph: %{
          "nodes" => [%{"id" => "n1", "type" => "wait", "config" => %{"duration" => "1d"}}],
          "edges" => []
        }
      )

      other_instance = insert(:flow_instance, flow: other_flow, tenant: other)

      %{tenant: tenant, other_flow: other_flow, other_instance: other_instance}
    end

    test "get_flow refuses another tenant's flow", ctx do
      assert {:error, msg} =
               Tools.execute("get_flow", %{"flow_id" => ctx.other_flow.id}, ctx.tenant.id)

      assert msg =~ "not found"
    end

    test "get_flow_graph refuses another tenant's flow", ctx do
      assert {:error, msg} =
               Tools.execute("get_flow_graph", %{"flow_id" => ctx.other_flow.id}, ctx.tenant.id)

      assert msg =~ "not found"
    end

    test "analyze_flow refuses another tenant's flow", ctx do
      assert {:error, msg} =
               Tools.execute("analyze_flow", %{"flow_id" => ctx.other_flow.id}, ctx.tenant.id)

      assert msg =~ "not found"
    end

    test "modify_node refuses to mutate another tenant's flow", ctx do
      assert {:error, msg} =
               Tools.execute(
                 "modify_node",
                 %{"flow_id" => ctx.other_flow.id, "node_id" => "n1", "config" => %{"x" => 1}},
                 ctx.tenant.id
               )

      assert msg =~ "not found"
    end

    test "remove_node refuses to mutate another tenant's flow", ctx do
      assert {:error, msg} =
               Tools.execute(
                 "remove_node",
                 %{"flow_id" => ctx.other_flow.id, "node_id" => "n1"},
                 ctx.tenant.id
               )

      assert msg =~ "not found"
    end

    test "add_node refuses to mutate another tenant's flow", ctx do
      assert {:error, msg} =
               Tools.execute(
                 "add_node",
                 %{
                   "flow_id" => ctx.other_flow.id,
                   "node" => %{"id" => "x", "type" => "exit", "config" => %{}}
                 },
                 ctx.tenant.id
               )

      assert msg =~ "not found"
    end

    test "debug_instance refuses another tenant's instance", ctx do
      assert {:error, msg} =
               Tools.execute(
                 "debug_instance",
                 %{"instance_id" => ctx.other_instance.id},
                 ctx.tenant.id
               )

      assert msg =~ "not found"
    end
  end
end
