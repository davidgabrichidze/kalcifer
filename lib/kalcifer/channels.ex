defmodule Kalcifer.Channels do
  @moduledoc false

  import Ecto.Query

  alias Kalcifer.Channels.Delivery
  alias Kalcifer.Repo

  def create_delivery(attrs) do
    %Delivery{}
    |> Delivery.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_delivery_status(delivery, new_status, attrs \\ %{}) do
    delivery
    |> Delivery.status_changeset(new_status, attrs)
    |> Repo.update()
  end

  def get_delivery(id) do
    Repo.get(Delivery, id)
  end

  def get_delivery_by_provider_message_id(provider_message_id) do
    Repo.get_by(Delivery, provider_message_id: provider_message_id)
  end

  @doc "Appends an engagement event (open, click, read, reply, seen...) to a delivery."
  def append_delivery_event(delivery, event) when is_map(event) do
    stamped = Map.put_new(event, "at", DateTime.utc_now() |> DateTime.to_iso8601())

    # Append at the DB level (array_append) instead of a read-modify-write on
    # the in-memory struct: concurrent provider callbacks (open, click, read...)
    # would otherwise each load the same `events` list and clobber each other,
    # silently dropping every event but the last writer's.
    query = from(d in Delivery, where: d.id == ^delivery.id)

    case Repo.update_all(query, push: [events: stamped]) do
      {1, _} -> {:ok, get_delivery(delivery.id)}
      {0, _} -> {:error, :not_found}
    end
  end

  @doc "List deliveries for a flow's instances, newest first."
  def list_deliveries(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    instance_id = Keyword.get(opts, :instance_id)
    tenant_id = Keyword.get(opts, :tenant_id)
    status = Keyword.get(opts, :status)

    query = from(d in Delivery, order_by: [desc: d.inserted_at], limit: ^limit)

    query =
      if instance_id, do: from(d in query, where: d.instance_id == ^instance_id), else: query

    query = if tenant_id, do: from(d in query, where: d.tenant_id == ^tenant_id), else: query
    query = if status, do: from(d in query, where: d.status == ^status), else: query

    Repo.all(query)
  end

  @doc "Delivery stats summary for a tenant."
  def delivery_stats(tenant_id) do
    from(d in Delivery,
      where: d.tenant_id == ^tenant_id,
      group_by: d.status,
      select: {d.status, count(d.id)}
    )
    |> Repo.all()
    |> Map.new()
  end
end
