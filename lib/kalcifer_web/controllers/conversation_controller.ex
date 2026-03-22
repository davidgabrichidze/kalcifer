defmodule KalciferWeb.ConversationController do
  use KalciferWeb, :controller

  alias Kalcifer.AI.Context

  @doc "GET /api/v1/conversations — list conversations for the dev tenant."
  def index(conn, params) do
    tenant_id = resolve_dev_tenant()
    opts = []
    opts = if params["status"], do: [status: params["status"]] ++ opts, else: opts
    opts = if params["kind"], do: [kind: params["kind"]] ++ opts, else: opts

    conversations =
      tenant_id
      |> Context.list_conversations(opts)
      |> Enum.map(&serialize/1)

    json(conn, %{conversations: conversations})
  end

  @doc "GET /api/v1/conversations/:id — get conversation with messages."
  def show(conn, %{"id" => id}) do
    case Context.get_conversation_with_messages(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Conversation not found"})

      conv ->
        json(conn, %{
          conversation: serialize(conv),
          messages:
            Enum.map(conv.messages, fn m ->
              %{
                id: m.id,
                role: m.role,
                content: m.content,
                tool_calls: m.tool_calls,
                timestamp: m.inserted_at
              }
            end)
        })
    end
  end

  @doc "POST /api/v1/conversations/:id/archive"
  def archive(conn, %{"id" => id}) do
    case Context.get_conversation(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Conversation not found"})

      conv ->
        {:ok, archived} = Context.archive_conversation(conv)
        json(conn, %{conversation: serialize(archived)})
    end
  end

  defp serialize(conv) do
    %{
      id: conv.id,
      title: conv.title,
      status: conv.status,
      kind: conv.kind,
      entity_type: conv.entity_type,
      entity_id: conv.entity_id,
      updated_at: conv.updated_at,
      inserted_at: conv.inserted_at
    }
  end

  # Same pattern as ChatController — in production would use auth
  defp resolve_dev_tenant do
    alias Kalcifer.Repo
    alias Kalcifer.Tenants.Tenant

    case Repo.get_by(Tenant, name: "Demo Tenant") do
      %Tenant{id: id} -> id
      nil -> raise "Demo Tenant not found — start a chat first"
    end
  end
end
