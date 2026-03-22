defmodule Kalcifer.AI.Tools do
  @moduledoc """
  Tool definitions and executor for AI-assisted flow management.

  Defines tools in Claude API format and executes them against
  the Kalcifer.Flows context. Each tool maps to existing context
  functions — no new business logic here.
  """

  alias Kalcifer.AI.Context
  alias Kalcifer.Engine.NodeRegistry
  alias Kalcifer.Flows

  require Logger

  # ── Tool Definitions (Claude API format) ──────────────────────

  @doc "Returns list of tool definitions for the Claude API."
  @spec definitions() :: list(map())
  def definitions do
    [
      classify_session_tool(),
      list_flows_tool(),
      get_flow_tool(),
      create_flow_tool(),
      list_node_types_tool(),
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
