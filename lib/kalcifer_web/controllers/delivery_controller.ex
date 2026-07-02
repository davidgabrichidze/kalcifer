defmodule KalciferWeb.DeliveryController do
  use KalciferWeb, :controller

  alias Kalcifer.Channels

  @doc "GET /api/v1/deliveries — list deliveries with optional filters"
  def index(conn, params) do
    tenant_id = KalciferWeb.TenantResolver.resolve_id(conn)

    opts = [tenant_id: tenant_id]

    opts =
      if params["instance_id"],
        do: Keyword.put(opts, :instance_id, params["instance_id"]),
        else: opts

    opts = if params["status"], do: Keyword.put(opts, :status, params["status"]), else: opts

    opts =
      if params["limit"],
        do: Keyword.put(opts, :limit, parse_int(params["limit"], 50)),
        else: opts

    deliveries = Channels.list_deliveries(opts)

    json(conn, %{
      data:
        Enum.map(deliveries, fn d ->
          %{
            id: d.id,
            channel: d.channel,
            status: d.status,
            recipient: d.recipient,
            provider: d.provider,
            provider_message_id: d.provider_message_id,
            error: d.error,
            events: d.events,
            sent_at: d.sent_at,
            delivered_at: d.delivered_at,
            failed_at: d.failed_at,
            inserted_at: d.inserted_at
          }
        end)
    })
  end

  @doc "GET /api/v1/deliveries/stats — delivery counts by status"
  def stats(conn, _params) do
    tenant_id = KalciferWeb.TenantResolver.resolve_id(conn)
    stats = Channels.delivery_stats(tenant_id)

    json(conn, %{
      data: %{
        pending: Map.get(stats, "pending", 0),
        sent: Map.get(stats, "sent", 0),
        delivered: Map.get(stats, "delivered", 0),
        bounced: Map.get(stats, "bounced", 0),
        failed: Map.get(stats, "failed", 0)
      }
    })
  end

  @doc "POST /api/v1/deliveries/:id/status — update delivery status (webhook callback)"
  def update_status(conn, %{"id" => id, "status" => new_status} = params) do
    case Channels.get_delivery(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Delivery not found"})

      delivery ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        attrs =
          case new_status do
            "sent" -> %{sent_at: now, provider_message_id: params["provider_message_id"]}
            "delivered" -> %{delivered_at: now}
            "failed" -> %{failed_at: now, error: params["error"]}
            "bounced" -> %{failed_at: now, error: params["error"] || "bounced"}
            _ -> %{}
          end

        case Channels.update_delivery_status(delivery, new_status, attrs) do
          {:ok, updated} ->
            json(conn, %{data: %{id: updated.id, status: updated.status}})

          {:error, _changeset} ->
            conn |> put_status(422) |> json(%{error: "Invalid status update"})
        end
    end
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
end
