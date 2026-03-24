defmodule KalciferWeb.ConversationController do
  use KalciferWeb, :controller

  alias Kalcifer.AI.Context

  @doc "GET /api/v1/conversations — list conversations for the dev tenant."
  def index(conn, params) do
    tenant_id = resolve_dev_tenant(conn)
    opts = []
    opts = if params["kind"], do: [kind: params["kind"]] ++ opts, else: opts

    # status=all returns both active and archived; default is "active"
    status = params["status"]

    conversations =
      if status == "all" do
        active = Context.list_conversations(tenant_id, [status: "active"] ++ opts)
        archived = Context.list_conversations(tenant_id, [status: "archived"] ++ opts)
        Enum.map(active ++ archived, &serialize/1)
      else
        opts = if status, do: [status: status] ++ opts, else: opts

        tenant_id
        |> Context.list_conversations(opts)
        |> Enum.map(&serialize/1)
      end

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

  @doc "PUT /api/v1/conversations/:id — rename a conversation."
  def update(conn, %{"id" => id} = params) do
    case Context.get_conversation(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Conversation not found"})

      conv ->
        title = params["title"] || ""

        case Context.rename_conversation(conv, title) do
          {:ok, renamed} ->
            json(conn, %{conversation: serialize(renamed)})

          {:error, changeset} ->
            errors =
              Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

            conn |> put_status(422) |> json(%{errors: errors})
        end
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

  @doc "DELETE /api/v1/conversations/:id — only unclassified conversations."
  def delete(conn, %{"id" => id}) do
    case Context.get_conversation(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Conversation not found"})

      %{kind: kind} when not is_nil(kind) ->
        conn
        |> put_status(422)
        |> json(%{error: "Classified conversations cannot be deleted, archive instead"})

      conv ->
        {:ok, _} = Context.delete_conversation(conv)
        conn |> put_status(200) |> json(%{ok: true})
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

  defp resolve_dev_tenant(conn), do: KalciferWeb.TenantResolver.resolve_id(conn)
end
