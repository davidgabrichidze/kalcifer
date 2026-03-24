defmodule Kalcifer.Audit do
  @moduledoc """
  Audit log for tracking actions performed on resources.

  Actions are recorded with:
  - actor: who did it ("system", "api", user email, etc.)
  - action: what happened (create, update, delete, activate, etc.)
  - resource_type: what kind of thing ("flow", "tenant", "conversation", etc.)
  - resource_id: which specific resource
  - details: additional context (map)
  """

  import Ecto.Query

  alias Kalcifer.Audit.Entry
  alias Kalcifer.Repo

  @doc "Record an audit log entry."
  def log(tenant_id, attrs) do
    %Entry{}
    |> Entry.changeset(Map.put(attrs, :tenant_id, tenant_id))
    |> Repo.insert()
  end

  @doc "List audit log entries for a tenant, newest first."
  def list(tenant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    resource_type = Keyword.get(opts, :resource_type)

    query =
      from(e in Entry,
        where: e.tenant_id == ^tenant_id,
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: ^limit,
        offset: ^offset
      )

    query =
      if resource_type do
        from(e in query, where: e.resource_type == ^resource_type)
      else
        query
      end

    Repo.all(query)
  end

  @doc "List audit entries for a specific resource."
  def for_resource(resource_type, resource_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    from(e in Entry,
      where: e.resource_type == ^resource_type,
      where: e.resource_id == ^resource_id,
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end
end
