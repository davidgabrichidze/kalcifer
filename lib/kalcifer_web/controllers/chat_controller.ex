defmodule KalciferWeb.ChatController do
  use KalciferWeb, :controller

  alias Kalcifer.AI.{Client, Context, Tools}

  @doc """
  POST /api/v1/chat

  Accepts:
    - `messages`: list of `%{"role" => "user", "content" => "..."}`
    - `conversation_id` (optional): existing conversation to continue

  Streams the AI response back as Server-Sent Events.

  SSE events:
    - `init`       — conversation_id (sent first, always)
    - `delta`      — streaming text chunk
    - `tool_start` — tool execution started
    - `tool_done`  — tool execution finished
    - `done`       — full text of final response
    - `error`      — error message
  """
  def create(conn, %{"messages" => messages} = params) do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    tenant_id = resolve_dev_tenant()

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

    callback = fn
      {:text_delta, text} ->
        chunk_sse(conn, "delta", %{text: text})

      {:tool_use, _id, name, input} ->
        chunk_sse(conn, "tool_start", %{tool: name, input: input})

      {:tool_result, "classify_session" = name, result} ->
        # Send both tool_done and a special session_classified event
        chunk_sse(conn, "tool_done", %{tool: name, result: result})

        case Jason.decode(result) do
          {:ok, %{"classified" => true} = data} ->
            chunk_sse(conn, "session_classified", %{
              kind: data["kind"],
              title: data["title"],
              reason: data["reason"]
            })

          _ ->
            :ok
        end

      {:tool_result, name, result} ->
        chunk_sse(conn, "tool_done", %{tool: name, result: result})

      {:done, full_text} ->
        # Save assistant response to DB
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

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "messages parameter required"})
  end

  # ── Conversation resolution ──────────────────────────────────

  # If conversation_id given, load its history; otherwise create new.
  defp resolve_conversation(tenant_id, nil) do
    {:ok, conv} = Context.create_conversation(tenant_id)
    {conv.id, []}
  end

  defp resolve_conversation(tenant_id, conversation_id) do
    case Context.get_conversation_with_messages(conversation_id) do
      nil ->
        # Conversation not found — create new
        resolve_conversation(tenant_id, nil)

      conv ->
        history =
          Enum.map(conv.messages, fn msg ->
            %{role: msg.role, content: msg.content}
          end)

        {conv.id, history}
    end
  end

  # ── System prompt with memory ────────────────────────────────

  # Returns a memory block to append to the system prompt,
  # or nil if no memories exist (Client will use its default prompt).
  defp build_system_prompt(tenant_id) do
    memories = Context.recall_all(tenant_id)

    if Enum.empty?(memories) do
      # nil means Client.base_body will use its default_system_prompt
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

      # Append to default prompt rather than replacing it
      Client.default_system_prompt() <> memory_block_text
    end
  end

  # ── Dev tenant resolution ────────────────────────────────────

  # In dev mode without auth, find or create a demo tenant.
  # In production, this would come from the authenticated session.
  defp resolve_dev_tenant do
    alias Kalcifer.Repo
    alias Kalcifer.Tenants
    alias Kalcifer.Tenants.Tenant

    case Repo.get_by(Tenant, name: "Demo Tenant") do
      %Tenant{id: id} ->
        id

      nil ->
        {:ok, tenant} =
          Tenants.create_tenant(%{
            name: "Demo Tenant",
            api_key_hash: Tenants.hash_api_key("demo-dev-key")
          })

        tenant.id
    end
  end

  defp humanize_error(:max_tool_rounds),
    do: "ძალიან ბევრი ნაბიჯი დამჭირდა — სცადე უფრო მოკლე დავალებით."

  defp humanize_error({:api_error, status, _body}),
    do: "სერვისთან კავშირის პრობლემა (#{status}). სცადე თავიდან."

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
