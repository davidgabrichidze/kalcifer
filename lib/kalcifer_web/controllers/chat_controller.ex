defmodule KalciferWeb.ChatController do
  use KalciferWeb, :controller

  alias Kalcifer.AI.{AgentFlows, Client, Context, Tools}
  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Tenants

  @doc """
  POST /api/v1/chat

  Accepts:
    - `messages`: list of `%{"role" => "user", "content" => "..."}`
    - `conversation_id` (optional): existing conversation to continue

  Streams the AI response back as Server-Sent Events.

  SSE events:
    - `init`            — conversation_id (sent first, always)
    - `delta`           — streaming text chunk
    - `tool_start`      — tool execution started
    - `tool_done`       — tool execution finished
    - `activity_start`  — agent flow instance started
    - `activity_step`   — engine node completed
    - `activity_done`   — agent flow completed
    - `done`            — full text of final response
    - `error`           — error message
  """
  def create(conn, %{"messages" => messages} = params) do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    tenant_id = resolve_dev_tenant(conn)

    # Resolve or create conversation
    {conversation_id, history} =
      resolve_conversation(tenant_id, params["conversation_id"])

    # Send conversation_id to frontend immediately
    chunk_sse(conn, "init", %{conversation_id: conversation_id})

    # Save the new user message(s)
    new_user_messages =
      Enum.filter(messages, fn msg -> msg["role"] == "user" end)

    for msg <- new_user_messages do
      Context.add_message(conversation_id, "user", msg["content"])
    end

    # Build full message list: history + new messages
    api_messages =
      history ++
        Enum.map(messages, fn msg ->
          %{role: msg["role"], content: msg["content"]}
        end)

    # Load operator memory into system prompt
    system_prompt = build_system_prompt(tenant_id)

    # Try engine-based execution; fall back to direct chat on failure
    case start_agent_flow(conn, tenant_id, conversation_id, api_messages, system_prompt) do
      {:ok, conn} ->
        conn

      {:error, _reason} ->
        # Fallback: direct chat_with_tools (no engine)
        run_direct_chat(conn, tenant_id, conversation_id, api_messages, system_prompt)
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "messages parameter required"})
  end

  # ── Engine-based execution ─────────────────────────────────

  defp start_agent_flow(conn, tenant_id, conversation_id, api_messages, system_prompt) do
    last_message = extract_last_user_message(api_messages)
    flow_result = select_agent_flow(tenant_id, last_message)

    case flow_result do
      {:ok, {flow, version}} ->
        instance_id = Ecto.UUID.generate()

        initial_context =
          %{
            "_initial_message" => last_message,
            "_messages" => api_messages,
            "_system_prompt" => system_prompt,
            "_tenant_id" => tenant_id,
            "_conversation_id" => conversation_id,
            "_ai_opts" => tenant_ai_opts(tenant_id)
          }

        # Subscribe to instance events before starting
        Phoenix.PubSub.subscribe(Kalcifer.PubSub, "instance:#{instance_id}")

        chunk_sse(conn, "activity_start", %{instance_id: instance_id})

        args = %{
          instance_id: instance_id,
          flow_id: flow.id,
          customer_id: conversation_id,
          tenant_id: tenant_id,
          version_number: version.version_number,
          graph: version.graph,
          initial_context: initial_context
        }

        case DynamicSupervisor.start_child(
               Kalcifer.Engine.FlowSupervisor,
               {FlowServer, args}
             ) do
          {:ok, _pid} ->
            conn = listen_for_events(conn, %{conversation_id: conversation_id, full_text: nil})
            {:ok, conn}

          {:error, reason} ->
            Phoenix.PubSub.unsubscribe(Kalcifer.PubSub, "instance:#{instance_id}")
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp listen_for_events(conn, state) do
    receive do
      # Agent node: streaming text delta
      %{type: "agent_text_delta", payload: %{text: text}} ->
        chunk_sse(conn, "delta", %{text: text})
        listen_for_events(conn, state)

      # Agent node: tool execution started
      %{type: "agent_tool_start", payload: payload} ->
        chunk_sse(conn, "tool_start", %{tool: payload.tool, input: payload.input})
        listen_for_events(conn, state)

      # Agent node: tool execution done
      %{type: "agent_tool_done", payload: payload} ->
        chunk_sse(conn, "tool_done", %{tool: payload.tool, result: payload.result})
        maybe_emit_session_classified(conn, payload.tool, payload.result)
        listen_for_events(conn, state)

      # Agent node: full response ready — save to DB immediately
      %{type: "agent_done", payload: %{text: text}} ->
        # Save even empty responses — ensures conversation history is complete
        content = if text && text != "", do: text, else: "(ხელსაწყოების გამოყენება)"
        Context.add_message(state.conversation_id, "assistant", content)

        listen_for_events(conn, %{state | full_text: text})

      # Engine: node execution completed (for activity indicator)
      %{type: "node_executed", payload: payload} ->
        chunk_sse(conn, "activity_step", %{
          node_id: payload.node_id,
          node_type: payload.node_type,
          status: "completed"
        })

        listen_for_events(conn, state)

      # Engine: flow completed
      %{type: "instance_completed"} ->
        chunk_sse(conn, "done", %{text: state.full_text || ""})
        chunk_sse(conn, "activity_done", %{status: "completed"})
        conn

      # Engine: flow failed
      %{type: "instance_failed"} ->
        chunk_sse(conn, "error", %{message: humanize_error(:agent_flow_failed)})
        chunk_sse(conn, "activity_done", %{status: "failed"})
        conn

      # Catch-all: log and continue (prevents stuck loop on unexpected messages)
      unexpected ->
        require Logger
        Logger.debug("listen_for_events: ignoring unexpected message: #{inspect(unexpected)}")
        listen_for_events(conn, state)
    after
      # 3 minute timeout
      180_000 ->
        chunk_sse(conn, "error", %{message: humanize_error(:timeout)})
        conn
    end
  end

  # ── Direct chat fallback (no engine) ───────────────────────

  defp run_direct_chat(conn, tenant_id, conversation_id, api_messages, system_prompt) do
    callback = fn
      {:text_delta, text} ->
        chunk_sse(conn, "delta", %{text: text})

      {:tool_use, _id, name, input} ->
        chunk_sse(conn, "tool_start", %{tool: name, input: input})

      {:tool_result, "classify_session" = name, result} ->
        chunk_sse(conn, "tool_done", %{tool: name, result: result})
        maybe_emit_session_classified(conn, name, result)

      {:tool_result, name, result} ->
        chunk_sse(conn, "tool_done", %{tool: name, result: result})

      {:done, full_text} ->
        Context.add_message(conversation_id, "assistant", full_text)
        chunk_sse(conn, "done", %{text: full_text})

      {:error, reason} ->
        chunk_sse(conn, "error", %{message: humanize_error(reason)})
    end

    tool_ctx = %{conversation_id: conversation_id}

    tool_executor = fn name, input ->
      Tools.execute(name, input, tenant_id, tool_ctx)
    end

    opts = if system_prompt, do: [system: system_prompt], else: []
    opts = opts ++ tenant_ai_opts(tenant_id)

    case Client.chat_with_tools(
           api_messages,
           Tools.definitions(),
           tool_executor,
           callback,
           opts
         ) do
      {:ok, _full_text} ->
        conn

      {:error, reason} ->
        chunk_sse(conn, "error", %{message: humanize_error(reason)})
        conn
    end
  end

  # ── Conversation resolution ──────────────────────────────────

  defp resolve_conversation(tenant_id, nil) do
    {:ok, conv} = Context.create_conversation(tenant_id)
    {conv.id, []}
  end

  # Cap the history re-sent to the model each turn so a long-running
  # conversation can't grow past the context window (which would 400 every
  # subsequent request and brick the conversation).
  @history_limit 100

  defp resolve_conversation(tenant_id, conversation_id) do
    case Context.get_conversation(tenant_id, conversation_id) do
      nil ->
        # Missing or another tenant's conversation — start a fresh one.
        resolve_conversation(tenant_id, nil)

      conv ->
        {conv.id, Context.recent_api_messages(conv.id, @history_limit)}
    end
  end

  # ── System prompt with memory ────────────────────────────────

  defp build_system_prompt(tenant_id) do
    memories = Context.recall_all(tenant_id)

    if Enum.empty?(memories) do
      nil
    else
      memory_block =
        memories
        |> Enum.map(fn m -> "- #{m.key}: #{m.value}" end)
        |> Enum.join("\n")

      memory_block_text = """

      ## რაც მახსოვს ამ მომხმარებლის შესახებ:
      #{memory_block}

      გამოიყენე ეს ინფორმაცია საუბარში ბუნებრივად — ნუ ჩამოთვლი რა გახსოვს,
      უბრალოდ იცოდე და გაითვალისწინე.
      """

      Client.default_system_prompt() <> memory_block_text
    end
  end

  # ── Helpers ────────────────────────────────────────────────────

  @council_keywords ~w(council საბჭო დაფიქრდი ანალიზი deliberate think_deep)

  defp select_agent_flow(tenant_id, message) do
    if council_request?(message) do
      AgentFlows.ensure_council_flow(tenant_id)
    else
      AgentFlows.ensure_simple_flow(tenant_id)
    end
  end

  defp council_request?(message) when is_binary(message) do
    lower = String.downcase(message)
    Enum.any?(@council_keywords, &String.contains?(lower, &1))
  end

  defp council_request?(_), do: false

  defp extract_last_user_message(messages) do
    messages
    |> Enum.filter(fn msg -> msg.role == "user" or msg[:role] == "user" end)
    |> List.last()
    |> case do
      %{content: content} -> content
      _ -> ""
    end
  end

  defp resolve_dev_tenant(conn), do: KalciferWeb.TenantResolver.resolve_id(conn)

  defp tenant_ai_opts(tenant_id) do
    case Tenants.get_tenant(tenant_id) do
      nil ->
        []

      tenant ->
        ai = Tenants.ai_config(tenant)

        opts = []
        opts = if ai.provider, do: [{:provider, ai.provider} | opts], else: opts
        opts = if ai.model, do: [{:model, ai.model} | opts], else: opts
        opts = if ai.api_key, do: [{:api_key, ai.api_key} | opts], else: opts
        opts
    end
  end

  defp maybe_emit_session_classified(conn, "classify_session", result) do
    case Jason.decode(result) do
      {:ok, %{"classified" => true} = data} ->
        event = %{
          kind: data["kind"],
          title: data["title"],
          reason: data["reason"]
        }

        event =
          if data["flow_id"], do: Map.put(event, :flow_id, data["flow_id"]), else: event

        chunk_sse(conn, "session_classified", event)

      _ ->
        :ok
    end
  end

  defp maybe_emit_session_classified(_conn, _tool, _result), do: :ok

  defp humanize_error(:max_tool_rounds),
    do: "ძალიან ბევრი ნაბიჯი დამჭირდა — სცადე უფრო მოკლე დავალებით."

  defp humanize_error({:api_error, status, _body}),
    do: "სერვისთან კავშირის პრობლემა (#{status}). სცადე თავიდან."

  defp humanize_error(:agent_flow_failed),
    do: "რაღაც შეცდომა მოხდა. სცადე თავიდან."

  defp humanize_error(:timeout),
    do: "დრო ამოიწურა. სცადე თავიდან."

  defp humanize_error(reason) when is_binary(reason), do: reason

  defp humanize_error(_reason),
    do: "რაღაც შეცდომა მოხდა. სცადე თავიდან."

  defp chunk_sse(conn, event, data) do
    payload = "event: #{event}\ndata: #{Jason.encode!(data)}\n\n"

    case chunk(conn, payload) do
      {:ok, _conn} -> conn
      {:error, :closed} -> conn
    end
  end
end
