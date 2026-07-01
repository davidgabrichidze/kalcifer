defmodule Kalcifer.Customers do
  @moduledoc false

  import Ecto.Query

  alias Kalcifer.Customers.Customer
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

  @doc """
  Returns coverage percentages for a list of field names across a tenant's customers.

  For each field name, computes what percentage of customers have a non-nil value.
  Fields are checked against both top-level schema fields (email, phone, name)
  and the `properties` JSONB column.

  Returns `%{field_name => float()}` where float is 0.0–100.0.
  """
  def field_coverage(tenant_id, field_names) when is_list(field_names) do
    total =
      Customer
      |> where(tenant_id: ^tenant_id)
      |> select([c], count(c.id))
      |> Repo.one()

    if total == 0 do
      Map.new(field_names, fn f -> {f, 0.0} end)
    else
      Map.new(field_names, fn field ->
        non_null_count = count_non_null(tenant_id, field, total)
        {field, Float.round(non_null_count / total * 100, 1)}
      end)
    end
  end

  @top_level_fields ~w(email phone name external_id)

  defp count_non_null(tenant_id, field, _total) when field in @top_level_fields do
    field_atom = String.to_existing_atom(field)

    Customer
    |> where(tenant_id: ^tenant_id)
    |> where([c], not is_nil(field(c, ^field_atom)))
    |> select([c], count(c.id))
    |> Repo.one()
  end

  defp count_non_null(tenant_id, field, _total) do
    Customer
    |> where(tenant_id: ^tenant_id)
    |> where([c], fragment("? -> ? IS NOT NULL", c.properties, ^field))
    |> select([c], count(c.id))
    |> Repo.one()
  end
end
