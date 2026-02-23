defmodule KalciferWeb.WebhookController do
  use KalciferWeb, :controller

  alias Kalcifer.Channels

  def sendgrid(conn, %{"event" => events}) when is_list(events) do
    Enum.each(events, &process_sendgrid_event/1)

    conn
    |> put_status(:ok)
    |> json(%{processed: length(events)})
  end

  def sendgrid(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "expected event array"})
  end

  def twilio(conn, %{"MessageSid" => message_sid, "MessageStatus" => status}) do
    process_delivery_status(message_sid, status)

    conn
    |> put_status(:ok)
    |> json(%{ok: true})
  end

  def twilio(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing MessageSid or MessageStatus"})
  end

  defp process_sendgrid_event(%{"sg_message_id" => msg_id, "event" => event_type}) do
    status = map_sendgrid_status(event_type)
    process_delivery_status(msg_id, status)
  end

  defp process_sendgrid_event(_), do: :skip

  defp map_sendgrid_status("delivered"), do: "delivered"
  defp map_sendgrid_status("bounce"), do: "bounced"
  defp map_sendgrid_status("dropped"), do: "failed"
  defp map_sendgrid_status("deferred"), do: "sent"
  defp map_sendgrid_status(_), do: nil

  defp process_delivery_status(_provider_msg_id, nil), do: :skip

  defp process_delivery_status(provider_msg_id, status) do
    import Ecto.Query

    case Kalcifer.Repo.one(
           from(d in Kalcifer.Channels.Delivery,
             where: d.provider_message_id == ^provider_msg_id
           )
         ) do
      nil ->
        :not_found

      delivery ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        attrs =
          case status do
            "delivered" -> %{delivered_at: now}
            "failed" -> %{failed_at: now}
            "bounced" -> %{failed_at: now}
            _ -> %{}
          end

        Channels.update_delivery_status(delivery, status, attrs)
    end
  end
end
