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

  def add_tag(customer, tag) when is_binary(tag) do
    tags = Enum.uniq([tag | customer.tags])

    customer
    |> Ecto.Changeset.change(tags: tags)
    |> Repo.update()
  end

  def remove_tag(customer, tag) when is_binary(tag) do
    tags = List.delete(customer.tags, tag)

    customer
    |> Ecto.Changeset.change(tags: tags)
    |> Repo.update()
  end

  def update_preferences(customer, preferences) when is_map(preferences) do
    merged = Map.merge(customer.preferences, preferences)

    customer
    |> Ecto.Changeset.change(preferences: merged)
    |> Repo.update()
  end
end
