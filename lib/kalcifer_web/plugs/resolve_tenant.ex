defmodule KalciferWeb.Plugs.ResolveTenant do
  @moduledoc """
  Resolves the request's tenant once, up front, and assigns it as
  `:current_tenant` — or halts with 401 when there is none.

  Runs on routes the operator frontend shares with API-key callers, so it
  accepts either credential: a Google session token (via `UserAuth`, which
  must plug in first) or an API key. In dev/test it also honours the
  `x-tenant-id` header and the Demo Tenant fallback, which is what keeps the
  frontend usable before anyone logs in.

  Controllers downstream keep calling `TenantResolver.resolve/1`; it finds
  the assign this plug set and does no further work.
  """

  alias KalciferWeb.ErrorResponse
  alias KalciferWeb.TenantResolver

  def init(opts), do: opts

  def call(conn, _opts) do
    case TenantResolver.resolve_or_nil(conn) do
      nil ->
        ErrorResponse.send_error(
          conn,
          :unauthorized,
          "unauthorized",
          "Authentication required. Sign in, or pass an API key as " <>
            "'Authorization: Bearer <key>'."
        )

      tenant ->
        Plug.Conn.assign(conn, :current_tenant, tenant)
    end
  end
end
