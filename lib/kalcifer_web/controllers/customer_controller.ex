defmodule KalciferWeb.CustomerController do
  use KalciferWeb, :controller

  alias Kalcifer.Customers

  action_fallback KalciferWeb.FallbackController

  def index(conn, params) do
    tenant = conn.assigns.current_tenant
    opts = [limit: Map.get(params, "limit", 50), offset: Map.get(params, "offset", 0)]
    customers = Customers.list_customers(tenant.id, opts)
    json(conn, %{data: Enum.map(customers, &serialize/1)})
  end

  def create(conn, params) do
    tenant = conn.assigns.current_tenant
    attrs = Map.put(params, "tenant_id", tenant.id)

    case Customers.create_customer(attrs) do
      {:ok, customer} ->
        conn |> put_status(:created) |> json(%{data: serialize(customer)})

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def show(conn, %{"id" => id}) do
    tenant = conn.assigns.current_tenant

    case Customers.get_customer(id) do
      %{tenant_id: tid} = customer when tid == tenant.id ->
        json(conn, %{data: serialize(customer)})

      _ ->
        {:error, :not_found}
    end
  end

  def update(conn, %{"id" => id} = params) do
    tenant = conn.assigns.current_tenant

    with %{tenant_id: tid} = customer when tid == tenant.id <- Customers.get_customer(id),
         {:ok, updated} <- Customers.update_customer(customer, params) do
      json(conn, %{data: serialize(updated)})
    else
      nil -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def add_tags(conn, %{"customer_id" => id, "tags" => tags}) when is_list(tags) do
    tenant = conn.assigns.current_tenant

    with %{tenant_id: tid} = customer when tid == tenant.id <- Customers.get_customer(id) do
      customer =
        Enum.reduce(tags, customer, fn tag, acc ->
          {:ok, updated} = Customers.add_tag(acc, tag)
          updated
        end)

      json(conn, %{data: serialize(customer)})
    else
      nil -> {:error, :not_found}
    end
  end

  def update_preferences(conn, %{"customer_id" => id, "preferences" => prefs})
      when is_map(prefs) do
    tenant = conn.assigns.current_tenant

    with %{tenant_id: tid} = customer when tid == tenant.id <- Customers.get_customer(id),
         {:ok, updated} <- Customers.update_preferences(customer, prefs) do
      json(conn, %{data: serialize(updated)})
    else
      nil -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp serialize(customer) do
    %{
      id: customer.id,
      external_id: customer.external_id,
      email: customer.email,
      phone: customer.phone,
      name: customer.name,
      properties: customer.properties,
      tags: customer.tags,
      preferences: customer.preferences,
      last_seen_at: customer.last_seen_at,
      inserted_at: customer.inserted_at
    }
  end
end
