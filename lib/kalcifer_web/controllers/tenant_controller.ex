defmodule KalciferWeb.TenantController do
  @moduledoc """
  Dev-frontend tenant listing for the tenant switcher. Exposes only
  id/name — sits on the unauthenticated dev pipeline alongside the
  browse endpoints.
  """

  use KalciferWeb, :controller

  alias Kalcifer.Tenants
  alias KalciferWeb.TenantResolver

  def index(conn, _params) do
    active = TenantResolver.resolve(conn)

    data =
      for tenant <- Tenants.list_tenants() do
        %{id: tenant.id, name: tenant.name, active: tenant.id == active.id}
      end

    json(conn, %{data: data})
  end
end
