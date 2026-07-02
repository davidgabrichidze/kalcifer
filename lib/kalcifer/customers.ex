defmodule Kalcifer.Customers do
  @moduledoc false

  import Ecto.Query

  alias Kalcifer.Customers.Customer
  alias Kalcifer.Customers.Segment
  alias Kalcifer.Customers.SegmentEvaluator
  alias Kalcifer.Customers.SegmentQuery
  alias Kalcifer.Repo

  def get_customer(id), do: Repo.get(Customer, id)

  def get_customer_by_external_id(tenant_id, external_id) do
    Repo.one(
      from(c in Customer,
        where: c.tenant_id == ^tenant_id and c.external_id == ^external_id
      )
    )
  end

  def list_customers(tenant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(c in Customer,
      where: c.tenant_id == ^tenant_id,
      order_by: [desc: c.inserted_at],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  def create_customer(attrs) do
    %Customer{}
    |> Customer.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_customer(customer, attrs) do
    customer
    |> Customer.update_changeset(attrs)
    |> Repo.update()
  end

  def upsert_customer(tenant_id, external_id, attrs \\ %{}) do
    case get_customer_by_external_id(tenant_id, external_id) do
      nil ->
        create_customer(Map.merge(attrs, %{tenant_id: tenant_id, external_id: external_id}))

      customer ->
        update_customer(customer, attrs)
    end
  end

  def delete_customer(customer) do
    Repo.delete(customer)
  end

  def add_tag(customer, tag) when is_binary(tag), do: add_tags(customer, [tag])

  def remove_tag(customer, tag) when is_binary(tag), do: remove_tags(customer, [tag])

  @doc "Adds a list of tags in a single update, preserving order and uniqueness."
  def add_tags(customer, tags) when is_list(tags) do
    merged = Enum.uniq(customer.tags ++ tags)

    customer
    |> Ecto.Changeset.change(tags: merged)
    |> Repo.update()
  end

  @doc "Removes a list of tags in a single update."
  def remove_tags(customer, tags) when is_list(tags) do
    remaining = customer.tags -- tags

    customer
    |> Ecto.Changeset.change(tags: remaining)
    |> Repo.update()
  end

  def update_preferences(customer, preferences) when is_map(preferences) do
    merged = Map.merge(customer.preferences, preferences)

    customer
    |> Ecto.Changeset.change(preferences: merged)
    |> Repo.update()
  end

  ## Segments

  def list_segments(tenant_id) do
    from(s in Segment,
      where: s.tenant_id == ^tenant_id,
      order_by: [asc: s.name]
    )
    |> Repo.all()
  end

  def get_segment(id), do: Repo.get(Segment, id)

  def create_segment(attrs) do
    %Segment{}
    |> Segment.changeset(attrs)
    |> Repo.insert()
  end

  def update_segment(segment, attrs) do
    segment
    |> Segment.changeset(attrs)
    |> Repo.update()
  end

  def delete_segment(segment), do: Repo.delete(segment)

  @doc "Lists members of a segment by evaluating its rules in the database."
  def list_segment_members(segment, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    segment
    |> SegmentQuery.members_query()
    |> order_by([c], desc: c.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def count_segment_members(segment) do
    segment
    |> SegmentQuery.members_query()
    |> select([c], count(c.id))
    |> Repo.one()
  end

  @doc "Returns ids of the tenant's segments the customer currently belongs to."
  def customer_segment_ids(customer) do
    customer.tenant_id
    |> list_segments()
    |> Enum.filter(&SegmentEvaluator.member?(customer, &1))
    |> Enum.map(& &1.id)
  end

  @doc """
  Returns coverage percentages for a list of field names across a tenant's customers.

  For each field name, computes what percentage of customers have a non-nil value.
  Fields are checked against both top-level schema fields (email, phone, name)
  and the `properties` JSONB column.

  Returns `%{field_name => float()}` where float is 0.0–100.0.
  """
  def field_coverage(tenant_id, field_names) when is_list(field_names) do
    # Single scan with one COUNT(*) FILTER (WHERE ...) per field instead of
    # a total query plus one count per field (N+1 over the customer table).
    selections =
      Enum.reduce(field_names, %{total: dynamic([c], count(c.id))}, fn field, acc ->
        Map.put(acc, field, non_null_count_expr(field))
      end)

    counts =
      Customer
      |> where(tenant_id: ^tenant_id)
      |> select(^selections)
      |> Repo.one()

    if counts.total == 0 do
      Map.new(field_names, fn f -> {f, 0.0} end)
    else
      Map.new(field_names, fn field ->
        {field, Float.round(Map.fetch!(counts, field) / counts.total * 100, 1)}
      end)
    end
  end

  @top_level_fields ~w(email phone name external_id)

  defp non_null_count_expr(field) when field in @top_level_fields do
    field_atom = String.to_existing_atom(field)
    dynamic([c], filter(count(c.id), not is_nil(field(c, ^field_atom))))
  end

  defp non_null_count_expr(field) do
    dynamic([c], filter(count(c.id), fragment("? -> ? IS NOT NULL", c.properties, ^field)))
  end
end
