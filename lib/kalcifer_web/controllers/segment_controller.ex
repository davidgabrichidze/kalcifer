defmodule KalciferWeb.SegmentController do
  use KalciferWeb, :controller

  alias Kalcifer.Customers

  action_fallback KalciferWeb.FallbackController

  def index(conn, _params) do
    tenant = conn.assigns.current_tenant
    segments = Customers.list_segments(tenant.id)
    json(conn, %{data: Enum.map(segments, &serialize/1)})
  end

  def create(conn, params) do
    tenant = conn.assigns.current_tenant
    attrs = Map.put(params, "tenant_id", tenant.id)

    with {:ok, segment} <- Customers.create_segment(attrs) do
      conn |> put_status(:created) |> json(%{data: serialize(segment)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, segment} <- fetch_segment(conn, id) do
      json(conn, %{data: serialize(segment)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, segment} <- fetch_segment(conn, id),
         {:ok, updated} <- Customers.update_segment(segment, params) do
      json(conn, %{data: serialize(updated)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, segment} <- fetch_segment(conn, id),
         {:ok, _deleted} <- Customers.delete_segment(segment) do
      send_resp(conn, :no_content, "")
    end
  end

  def members(conn, %{"segment_id" => id} = params) do
    with {:ok, segment} <- fetch_segment(conn, id) do
      opts = [
        limit: parse_int(params["limit"], 50),
        offset: parse_int(params["offset"], 0)
      ]

      members = Customers.list_segment_members(segment, opts)
      total = Customers.count_segment_members(segment)

      json(conn, %{
        data: Enum.map(members, &serialize_member/1),
        meta: %{total: total}
      })
    end
  end

  defp fetch_segment(conn, id) do
    tenant_id = conn.assigns.current_tenant.id

    case Customers.get_segment(id) do
      %{tenant_id: ^tenant_id} = segment -> {:ok, segment}
      _ -> {:error, :not_found}
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp serialize(segment) do
    %{
      id: segment.id,
      name: segment.name,
      description: segment.description,
      type: segment.type,
      rules: segment.rules,
      inserted_at: segment.inserted_at,
      updated_at: segment.updated_at
    }
  end

  defp serialize_member(customer) do
    %{
      id: customer.id,
      external_id: customer.external_id,
      email: customer.email,
      phone: customer.phone,
      name: customer.name,
      tags: customer.tags
    }
  end
end
