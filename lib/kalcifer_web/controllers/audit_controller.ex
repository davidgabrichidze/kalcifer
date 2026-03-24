defmodule KalciferWeb.AuditController do
  use KalciferWeb, :controller

  alias Kalcifer.Audit

  def index(conn, params) do
    tenant_id = KalciferWeb.TenantResolver.resolve_id(conn)

    opts = [
      limit: parse_int(params["limit"], 50),
      offset: parse_int(params["offset"], 0)
    ]

    opts =
      if params["resource_type"],
        do: Keyword.put(opts, :resource_type, params["resource_type"]),
        else: opts

    entries = Audit.list(tenant_id, opts)

    json(conn, %{
      data:
        Enum.map(entries, fn e ->
          %{
            id: e.id,
            actor: e.actor,
            action: e.action,
            resource_type: e.resource_type,
            resource_id: e.resource_id,
            details: e.details,
            timestamp: e.inserted_at
          }
        end)
    })
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end
end
