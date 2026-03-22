defmodule KalciferWeb.ChatController do
  use KalciferWeb, :controller

  alias Kalcifer.AI.Client
  alias Kalcifer.AI.Tools

  @doc """
  POST /api/v1/chat

  Accepts `{"messages": [{"role": "user", "content": "..."}]}`.
  Streams the AI response back as Server-Sent Events.

  Tool use flow:
  1. Non-streaming call with tools → check for tool_use
  2. Execute tools, send SSE events for each
  3. Stream final text response
  """
  def create(conn, %{"messages" => messages}) do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    api_messages =
      Enum.map(messages, fn msg ->
        %{role: msg["role"], content: msg["content"]}
      end)

    tenant_id = resolve_dev_tenant()

    callback = fn
      {:text_delta, text} ->
        chunk_sse(conn, "delta", %{text: text})

      {:tool_use, _id, name, input} ->
        chunk_sse(conn, "tool_start", %{tool: name, input: input})

      {:tool_result, name, result} ->
        chunk_sse(conn, "tool_done", %{tool: name, result: result})

      {:done, full_text} ->
        chunk_sse(conn, "done", %{text: full_text})

      {:error, reason} ->
        chunk_sse(conn, "error", %{message: inspect(reason)})
    end

    tool_executor = fn name, input ->
      Tools.execute(name, input, tenant_id)
    end

    case Client.chat_with_tools(
           api_messages,
           Tools.definitions(),
           tool_executor,
           callback
         ) do
      {:ok, _full_text} ->
        conn

      {:error, reason} ->
        chunk_sse(conn, "error", %{message: inspect(reason)})
        conn
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "messages parameter required"})
  end

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

  defp chunk_sse(conn, event, data) do
    payload = "event: #{event}\ndata: #{Jason.encode!(data)}\n\n"

    case chunk(conn, payload) do
      {:ok, _conn} -> conn
      {:error, :closed} -> conn
    end
  end
end
