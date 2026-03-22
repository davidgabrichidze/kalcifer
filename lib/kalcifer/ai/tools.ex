defmodule Kalcifer.AI.Tools do
  @moduledoc """
  Tool definitions and executor for AI-assisted flow management.

  Defines tools in Claude API format and executes them against
  the Kalcifer.Flows context. Each tool maps to existing context
  functions — no new business logic here.
  """

  alias Kalcifer.AI.Context
  alias Kalcifer.Engine.{GraphWalker, NodeRegistry}
  alias Kalcifer.Flows
  alias Kalcifer.Flows.FlowGraph

  require Logger

  # ── Tool Definitions (Claude API format) ──────────────────────

  @doc "Returns list of tool definitions for the Claude API."
  @spec definitions() :: list(map())
  def definitions do
    [
      classify_session_tool(),
      list_flows_tool(),
      get_flow_tool(),
      get_flow_graph_tool(),
      create_flow_tool(),
      add_node_tool(),
      modify_node_tool(),
      list_node_types_tool(),
      analyze_flow_tool(),
      debug_instance_tool(),
      remember_tool(),
      recall_tool()
    ]
  end

  defp classify_session_tool do
    %{
      name: "classify_session",
      description: """
      Propose a session type to the user. Use this when you understand what
      the user wants to do. The result is shown as a suggestion that the user
      confirms or rejects.

      Session types:
      - campaign: marketing campaign/journey (email sequences, onboarding, etc.)
      - flow: standalone automation flow (not marketing-specific)
      - analysis: reviewing metrics, funnel analysis, A/B results
      - debug: diagnosing a problem with an instance or flow

      Call this ONCE per session, when the purpose becomes clear.
      Include a suggested title for the session.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          kind: %{
            type: "string",
            enum: ["campaign", "flow", "analysis", "debug"],
            description: "The proposed session type"
          },
          title: %{
            type: "string",
            description: "A short, human-readable title for this session (e.g. 'Welcome კამპანია', 'Onboarding ფლოუ')"
          },
          reason: %{
            type: "string",
            description: "Brief explanation of why you think this is the right type (shown to user)"
          }
        },
        required: ["kind", "title"]
      }
    }
  end

  defp list_flows_tool do
    %{
      name: "list_flows",
      description: """
      List all flows for the current tenant. Optionally filter by status.
      Returns flow id, name, status, and description.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          status: %{
            type: "string",
            enum: ["draft", "active", "paused", "archived"],
            description: "Filter by status. Omit to list all."
          }
        },
        required: []
      }
    }
  end

  defp get_flow_tool do
    %{
      name: "get_flow",
      description: """
      Get detailed information about a specific flow by ID.
      Returns flow metadata, status, active version, and version count.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          flow_id: %{
            type: "string",
            description: "The UUID of the flow to retrieve."
          }
        },
        required: ["flow_id"]
      }
    }
  end

  defp create_flow_tool do
    %{
      name: "create_flow",
      description: """
      Create a new draft flow. The flow starts in "draft" status.
      After creation, a version with a graph must be added before activation.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          name: %{
            type: "string",
            description: "Human-readable name for the flow."
          },
          description: %{
            type: "string",
            description: "Optional description of what this flow does."
          }
        },
        required: ["name"]
      }
    }
  end

  defp get_flow_graph_tool do
    %{
      name: "get_flow_graph",
      description: """
      Get the full graph (nodes + edges) for a flow version.
      If no version is specified, returns the latest version's graph.
      Use this to understand the structure before adding or modifying nodes.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          flow_id: %{
            type: "string",
            description: "The UUID of the flow."
          },
          version_number: %{
            type: "integer",
            description: "Specific version number. Omit for latest."
          }
        },
        required: ["flow_id"]
      }
    }
  end

  defp add_node_tool do
    %{
      name: "add_node",
      description: """
      Add a new node to a flow's draft version and connect it with edges.
      Creates a new draft version if needed (latest version is published).

      The node needs a unique id, a type (from list_node_types), and config.
      Edges connect this node to existing nodes in the graph.

      After adding, the graph is validated automatically.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          flow_id: %{
            type: "string",
            description: "The UUID of the flow."
          },
          node: %{
            type: "object",
            description: "The node to add: {id, type, config}",
            properties: %{
              id: %{type: "string", description: "Unique node ID within the graph"},
              type: %{type: "string", description: "Node type (e.g. send_email, condition, wait)"},
              config: %{type: "object", description: "Node-specific configuration"}
            },
            required: ["id", "type"]
          },
          edges: %{
            type: "array",
            description: "Edges to add: [{source, target, branch?}]",
            items: %{
              type: "object",
              properties: %{
                source: %{type: "string"},
                target: %{type: "string"},
                branch: %{type: "string", description: "Branch key for condition/split nodes"}
              },
              required: ["source", "target"]
            }
          }
        },
        required: ["flow_id", "node"]
      }
    }
  end

  defp modify_node_tool do
    %{
      name: "modify_node",
      description: """
      Modify an existing node's configuration in a flow's draft version.
      Creates a new draft version if needed. Only updates the config —
      cannot change node type or ID.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          flow_id: %{
            type: "string",
            description: "The UUID of the flow."
          },
          node_id: %{
            type: "string",
            description: "The ID of the node to modify."
          },
          config: %{
            type: "object",
            description: "New config (merged with existing). Pass full config to replace."
          }
        },
        required: ["flow_id", "node_id", "config"]
      }
    }
  end

  defp analyze_flow_tool do
    %{
      name: "analyze_flow",
      description: """
      Analyze a flow's graph structure. Returns:
      - Preflight validation (errors, warnings)
      - Node count by category
      - Context dependencies (what data the flow needs)
      - Entry points and end nodes

      Use this to check if a flow is ready for activation.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          flow_id: %{
            type: "string",
            description: "The UUID of the flow."
          }
        },
        required: ["flow_id"]
      }
    }
  end

  defp debug_instance_tool do
    %{
      name: "debug_instance",
      description: """
      Inspect a flow instance's execution state. Returns:
      - Instance status, current nodes, context
      - Execution step history (what happened, in order)
      - Any errors or failures

      Use this to diagnose why an instance is stuck, failed, or behaving unexpectedly.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          instance_id: %{
            type: "string",
            description: "The UUID of the flow instance."
          }
        },
        required: ["instance_id"]
      }
    }
  end

  defp list_node_types_tool do
    %{
      name: "list_node_types",
      description: """
      List all available node types that can be used in flow graphs.
      Returns the type key and category for each registered node.
      """,
      input_schema: %{
        type: "object",
        properties: %{},
        required: []
      }
    }
  end

  defp remember_tool do
    %{
      name: "remember",
      description: """
      Save something to long-term memory. Use this to remember user preferences,
      project context, patterns, or anything useful for future conversations.
      Memory persists across chat sessions.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          key: %{
            type: "string",
            description: "A short key for the memory, e.g. 'preferred_language', 'project_name'"
          },
          value: %{
            type: "string",
            description: "The value to remember"
          },
          category: %{
            type: "string",
            enum: ["general", "preference", "pattern", "context"],
            description: "Category of the memory. Default: general"
          }
        },
        required: ["key", "value"]
      }
    }
  end

  defp recall_tool do
    %{
      name: "recall",
      description: """
      Recall memories from long-term storage. Use this at the start of
      conversations to remember user context, or when you need to check
      what you know about the user/project.
      Pass a specific key to recall one memory, or omit to recall all.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          key: %{
            type: "string",
            description: "Specific memory key to recall. Omit to list all memories."
          },
          category: %{
            type: "string",
            enum: ["general", "preference", "pattern", "context"],
            description: "Filter by category"
          }
        },
        required: []
      }
    }
  end

  # ── Tool Execution ────────────────────────────────────────────

  @doc """
  Executes a tool by name with the given input.
  Returns `{:ok, result_string}` or `{:error, reason}`.

  The `tenant_id` is injected by the caller (ChatController)
  so tools never need to resolve auth themselves.

  `ctx` is an optional map with session context (e.g. conversation_id)
  needed by tools like classify_session.
  """
  @spec execute(String.t(), map(), String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(tool_name, input, tenant_id, ctx \\ %{}) do
    Logger.info("AI tool call: #{tool_name} input=#{inspect(input)}")

    case do_execute(tool_name, input, tenant_id, ctx) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        Logger.warning("AI tool error: #{tool_name} reason=#{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("AI tool crash: #{tool_name} #{Exception.message(e)}")
      {:error, "Internal error executing #{tool_name}"}
  end

  defp do_execute("classify_session", input, _tenant_id, ctx) do
    conversation_id = Map.get(ctx, :conversation_id)

    unless conversation_id do
      {:error, "No active conversation to classify"}
    else
      kind = Map.fetch!(input, "kind")
      title = Map.get(input, "title")
      reason = Map.get(input, "reason", "")

      case Context.get_conversation(conversation_id) do
        nil ->
          {:error, "Conversation not found"}

        conv ->
          case Context.classify_conversation(conv, kind, title) do
            {:ok, classified} ->
              result = %{
                classified: true,
                kind: classified.kind,
                title: classified.title,
                reason: reason,
                needs_confirmation: true
              }

              {:ok, Jason.encode!(result, pretty: true)}

            {:error, changeset} ->
              {:error, "Classification failed: #{format_changeset_errors(changeset)}"}
          end
      end
    end
  end

  defp do_execute("list_flows", input, tenant_id, _ctx) do
    opts =
      case Map.get(input, "status") do
        nil -> []
        status -> [status: status]
      end

    flows = Flows.list_flows(tenant_id, opts)

    result =
      Enum.map(flows, fn f ->
        %{
          id: f.id,
          name: f.name,
          status: f.status,
          description: f.description
        }
      end)

    {:ok, Jason.encode!(result, pretty: true)}
  end

  defp do_execute("get_flow", %{"flow_id" => flow_id}, _tenant_id, _ctx) do
    case Flows.get_flow(flow_id) do
      nil ->
        {:error, "Flow not found: #{flow_id}"}

      flow ->
        flow = Kalcifer.Repo.preload(flow, :versions)

        result = %{
          id: flow.id,
          name: flow.name,
          status: flow.status,
          description: flow.description,
          active_version_id: flow.active_version_id,
          version_count: length(flow.versions),
          created_at: flow.inserted_at
        }

        {:ok, Jason.encode!(result, pretty: true)}
    end
  end

  defp do_execute("create_flow", input, tenant_id, _ctx) do
    attrs = %{
      name: Map.fetch!(input, "name"),
      description: Map.get(input, "description", "")
    }

    case Flows.create_flow(tenant_id, attrs) do
      {:ok, flow} ->
        result = %{
          id: flow.id,
          name: flow.name,
          status: flow.status,
          message: "Flow created successfully"
        }

        {:ok, Jason.encode!(result, pretty: true)}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)
        {:error, "Failed to create flow: #{errors}"}
    end
  end

  defp do_execute("get_flow_graph", input, _tenant_id, _ctx) do
    flow_id = Map.fetch!(input, "flow_id")
    version_number = Map.get(input, "version_number")

    with {:flow, flow} when not is_nil(flow) <- {:flow, Flows.get_flow(flow_id)},
         {:version, version} when not is_nil(version) <- {:version, resolve_version(flow, version_number)} do
      graph = version.graph || %{"nodes" => [], "edges" => []}

      result = %{
        flow_id: flow.id,
        flow_name: flow.name,
        version_number: version.version_number,
        version_status: version.status,
        nodes: Map.get(graph, "nodes", []),
        edges: Map.get(graph, "edges", []),
        node_count: length(Map.get(graph, "nodes", []))
      }

      {:ok, Jason.encode!(result, pretty: true)}
    else
      {:flow, nil} -> {:error, "Flow not found: #{flow_id}"}
      {:version, nil} -> {:error, "Version not found"}
    end
  end

  defp do_execute("add_node", input, _tenant_id, _ctx) do
    flow_id = Map.fetch!(input, "flow_id")
    new_node = Map.fetch!(input, "node")
    new_edges = Map.get(input, "edges", [])

    with {:flow, flow} when not is_nil(flow) <- {:flow, Flows.get_flow(flow_id)},
         {:version, version} when not is_nil(version) <- {:version, get_or_create_draft_version(flow)} do
      graph = version.graph || %{"nodes" => [], "edges" => []}
      nodes = Map.get(graph, "nodes", [])
      edges = Map.get(graph, "edges", [])

      # Check for duplicate node ID
      if Enum.any?(nodes, &(&1["id"] == new_node["id"])) do
        {:error, "Node with id '#{new_node["id"]}' already exists"}
      else
        # Build the node map
        node_map = %{
          "id" => Map.fetch!(new_node, "id"),
          "type" => Map.fetch!(new_node, "type"),
          "config" => Map.get(new_node, "config", %{})
        }

        # Build edge maps
        edge_maps =
          Enum.map(new_edges, fn e ->
            edge = %{"source" => e["source"], "target" => e["target"]}
            if e["branch"], do: Map.put(edge, "branch", e["branch"]), else: edge
          end)

        updated_graph = %{
          "nodes" => nodes ++ [node_map],
          "edges" => edges ++ edge_maps
        }

        # Validate
        warnings =
          case FlowGraph.validate(updated_graph) do
            :ok -> []
            {:error, errors} -> errors
          end

        # Persist
        {:ok, _updated} =
          version
          |> Ecto.Changeset.change(graph: updated_graph)
          |> Kalcifer.Repo.update()

        result = %{
          added_node: node_map["id"],
          added_edges: length(edge_maps),
          total_nodes: length(nodes) + 1,
          version_number: version.version_number,
          validation_warnings: warnings
        }

        {:ok, Jason.encode!(result, pretty: true)}
      end
    else
      {:flow, nil} -> {:error, "Flow not found: #{flow_id}"}
      {:version, nil} -> {:error, "No draft version available"}
    end
  end

  defp do_execute("modify_node", input, _tenant_id, _ctx) do
    flow_id = Map.fetch!(input, "flow_id")
    node_id = Map.fetch!(input, "node_id")
    new_config = Map.fetch!(input, "config")

    with {:flow, flow} when not is_nil(flow) <- {:flow, Flows.get_flow(flow_id)},
         {:version, version} when not is_nil(version) <- {:version, get_or_create_draft_version(flow)} do
      graph = version.graph || %{"nodes" => [], "edges" => []}
      nodes = Map.get(graph, "nodes", [])

      case Enum.find_index(nodes, &(&1["id"] == node_id)) do
        nil ->
          {:error, "Node '#{node_id}' not found in graph"}

        idx ->
          old_node = Enum.at(nodes, idx)
          updated_node = Map.put(old_node, "config", new_config)
          updated_nodes = List.replace_at(nodes, idx, updated_node)
          updated_graph = Map.put(graph, "nodes", updated_nodes)

          {:ok, _} =
            version
            |> Ecto.Changeset.change(graph: updated_graph)
            |> Kalcifer.Repo.update()

          result = %{
            modified_node: node_id,
            node_type: old_node["type"],
            version_number: version.version_number
          }

          {:ok, Jason.encode!(result, pretty: true)}
      end
    else
      {:flow, nil} -> {:error, "Flow not found: #{flow_id}"}
      {:version, nil} -> {:error, "No draft version available"}
    end
  end

  defp do_execute("analyze_flow", input, _tenant_id, _ctx) do
    flow_id = Map.fetch!(input, "flow_id")

    with {:flow, flow} when not is_nil(flow) <- {:flow, Flows.get_flow(flow_id)},
         {:version, version} when not is_nil(version) <- {:version, resolve_version(flow, nil)} do
      graph = version.graph || %{"nodes" => [], "edges" => []}
      nodes = Map.get(graph, "nodes", [])

      # Preflight
      preflight =
        case FlowGraph.preflight(graph, NodeRegistry) do
          {:ok, info} -> %{valid: true, warnings: Map.get(info, :warnings, []), context_deps: Map.get(info, :context_deps, [])}
          {:error, errors} -> %{valid: false, errors: errors}
        end

      # Node stats by category
      category_counts =
        Enum.reduce(nodes, %{}, fn node, acc ->
          category =
            case NodeRegistry.lookup(node["type"]) do
              {:ok, mod} ->
                if function_exported?(mod, :category, 0), do: to_string(mod.category()), else: "unknown"
              :error ->
                "unknown"
            end

          Map.update(acc, category, 1, &(&1 + 1))
        end)

      # Entry & end nodes
      entry_nodes =
        GraphWalker.entry_nodes(graph) |> Enum.map(& &1["id"])

      end_nodes =
        nodes
        |> Enum.filter(&(&1["type"] in ~w(exit goal_reached)))
        |> Enum.map(& &1["id"])

      result = %{
        flow_name: flow.name,
        flow_status: flow.status,
        version_number: version.version_number,
        version_status: version.status,
        node_count: length(nodes),
        edge_count: length(Map.get(graph, "edges", [])),
        categories: category_counts,
        entry_nodes: entry_nodes,
        end_nodes: end_nodes,
        preflight: preflight
      }

      {:ok, Jason.encode!(result, pretty: true)}
    else
      {:flow, nil} -> {:error, "Flow not found: #{flow_id}"}
      {:version, nil} -> {:error, "No versions found for this flow"}
    end
  end

  defp do_execute("debug_instance", input, _tenant_id, _ctx) do
    instance_id = Map.fetch!(input, "instance_id")

    alias Kalcifer.Engine.Persistence.{InstanceStore, StepStore}

    case InstanceStore.get_instance(instance_id) do
      nil ->
        {:error, "Instance not found: #{instance_id}"}

      instance ->
        # Load execution steps
        steps =
          StepStore.list_steps(instance_id)
          |> Enum.map(fn s ->
            step = %{
              node_id: s.node_id,
              node_type: s.node_type,
              status: s.status,
              started_at: s.started_at,
              completed_at: s.completed_at
            }

            step =
              if s.status == "failed" and s.error,
                do: Map.put(step, :error, s.error),
                else: step

            if s.output,
              do: Map.put(step, :output_keys, Map.keys(s.output)),
              else: step
          end)

        result = %{
          instance_id: instance.id,
          flow_id: instance.flow_id,
          status: instance.status,
          current_nodes: instance.current_nodes,
          version_number: instance.version_number,
          customer_id: instance.customer_id,
          dry_run: instance.dry_run,
          entered_at: instance.entered_at,
          completed_at: instance.completed_at,
          exit_reason: instance.exit_reason,
          context_keys: Map.keys(instance.context || %{}),
          step_count: length(steps),
          steps: steps
        }

        {:ok, Jason.encode!(result, pretty: true)}
    end
  end

  defp do_execute("list_node_types", _input, _tenant_id, _ctx) do
    nodes =
      NodeRegistry.list_all()
      |> Enum.map(fn {type, module} ->
        category =
          if function_exported?(module, :category, 0) do
            module.category() |> to_string()
          else
            "unknown"
          end

        %{type: type, category: category}
      end)
      |> Enum.sort_by(& &1.category)

    {:ok, Jason.encode!(nodes, pretty: true)}
  end

  defp do_execute("remember", input, tenant_id, _ctx) do
    key = Map.fetch!(input, "key")
    value = Map.fetch!(input, "value")
    category = Map.get(input, "category", "general")

    case Context.remember(tenant_id, key, value, category) do
      {:ok, _memory} ->
        {:ok, Jason.encode!(%{remembered: true, key: key})}

      {:error, changeset} ->
        {:error, "Failed to remember: #{format_changeset_errors(changeset)}"}
    end
  end

  defp do_execute("recall", input, tenant_id, _ctx) do
    case Map.get(input, "key") do
      nil ->
        # Recall all memories
        opts = case Map.get(input, "category") do
          nil -> []
          cat -> [category: cat]
        end

        memories = Context.recall_all(tenant_id, opts)

        result =
          Enum.map(memories, fn m ->
            %{key: m.key, value: m.value, category: m.category}
          end)

        {:ok, Jason.encode!(result, pretty: true)}

      key ->
        case Context.recall(tenant_id, key) do
          nil ->
            {:ok, Jason.encode!(%{found: false, key: key})}

          memory ->
            {:ok, Jason.encode!(%{found: true, key: memory.key, value: memory.value, category: memory.category})}
        end
    end
  end

  defp do_execute(unknown_tool, _input, _tenant_id, _ctx) do
    {:error, "Unknown tool: #{unknown_tool}"}
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp resolve_version(flow, nil) do
    # Latest version
    flow = Kalcifer.Repo.preload(flow, :versions)

    flow.versions
    |> Enum.sort_by(& &1.version_number, :desc)
    |> List.first()
  end

  defp resolve_version(flow, version_number) do
    Flows.get_version(flow.id, version_number)
  end

  defp get_or_create_draft_version(flow) do
    flow = Kalcifer.Repo.preload(flow, :versions)

    # Find existing draft
    draft =
      flow.versions
      |> Enum.filter(&(&1.status == "draft"))
      |> Enum.sort_by(& &1.version_number, :desc)
      |> List.first()

    if draft do
      draft
    else
      # Create new draft version based on latest
      latest =
        flow.versions
        |> Enum.sort_by(& &1.version_number, :desc)
        |> List.first()

      next_number = if latest, do: latest.version_number + 1, else: 1
      base_graph = if latest, do: latest.graph, else: %{"nodes" => [], "edges" => []}

      case Flows.create_version(flow, %{
             version_number: next_number,
             graph: base_graph,
             changelog: "Created by AI tool"
           }) do
        {:ok, version} -> version
        {:error, _} -> nil
      end
    end
  end

  defp format_changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end
end
