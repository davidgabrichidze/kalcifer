defmodule KalciferWeb.Plugs.DevOnly do
  @moduledoc """
  Guards endpoints that exist only for the local dev frontend and expose
  unscoped/global data (e.g. the tenant roster, engine-wide stats and logs).

  Passes the request through only when the dev-frontend flag
  `:allow_tenant_header` is on (dev/test); otherwise responds 404 so these
  routes are not reachable in production, where the same flag disables the
  x-tenant-id header they rely on.
  """

  alias KalciferWeb.ErrorResponse

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:kalcifer, :allow_tenant_header, false) do
      conn
    else
      ErrorResponse.send_error(conn, :not_found, "not_found", "Not found.")
    end
  end
end
