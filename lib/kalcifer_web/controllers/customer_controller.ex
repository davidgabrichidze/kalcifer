defmodule KalciferWeb.CustomerController do
  use KalciferWeb, :controller

  alias Kalcifer.Customers
  alias KalciferWeb.Params

  action_fallback KalciferWeb.FallbackController

  def index(conn, params) do
    tenant = conn.assigns.current_tenant

    with {:ok, page} <- Params.validate(params, Params.pagination_schema()) do
      customers = Customers.list_customers(tenant.id, limit: page.limit, offset: page.offset)
      json(conn, %{data: Enum.map(customers, &serialize/1)})
    end
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
    tenant_id = tenant.id

    with %{tenant_id: ^tenant_id} = customer <- Customers.get_customer(id),
         {:ok, updated} <- Customers.update_customer(customer, params) do
      json(conn, %{data: serialize(updated)})
    else
      nil -> {:error, :not_found}
      %{} -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def delete(conn, %{"id" => id}) do
    tenant = conn.assigns.current_tenant
    tenant_id = tenant.id

    with %{tenant_id: ^tenant_id} = customer <- Customers.get_customer(id),
         {:ok, _deleted} <- Customers.delete_customer(customer) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      %{} -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def add_tags(conn, %{"customer_id" => id, "tags" => tags}) when is_list(tags) do
    tenant = conn.assigns.current_tenant
    tenant_id = tenant.id

    with %{tenant_id: ^tenant_id} = customer <- Customers.get_customer(id),
         {:ok, updated} <- Customers.add_tags(customer, tags) do
      json(conn, %{data: serialize(updated)})
    else
      nil -> {:error, :not_found}
      %{} -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def remove_tags(conn, %{"customer_id" => id, "tags" => tags}) when is_list(tags) do
    tenant = conn.assigns.current_tenant
    tenant_id = tenant.id

    with %{tenant_id: ^tenant_id} = customer <- Customers.get_customer(id),
         {:ok, updated} <- Customers.remove_tags(customer, tags) do
      json(conn, %{data: serialize(updated)})
    else
      nil -> {:error, :not_found}
      %{} -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def update_preferences(conn, %{"customer_id" => id, "preferences" => prefs})
      when is_map(prefs) do
    tenant = conn.assigns.current_tenant
    tenant_id = tenant.id

    with %{tenant_id: ^tenant_id} = customer <- Customers.get_customer(id),
         {:ok, updated} <- Customers.update_preferences(customer, prefs) do
      json(conn, %{data: serialize(updated)})
    else
      nil -> {:error, :not_found}
      %{} -> {:error, :not_found}
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
