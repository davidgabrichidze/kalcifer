defmodule KalciferWeb.TenantResolver do
  @moduledoc """
  Shared tenant resolution for controllers that serve both authenticated
  (via ApiKeyAuth plug) and unauthenticated (dev frontend) routes.

  Resolution order:
  1. `conn.assigns[:current_tenant]` — set by the ApiKeyAuth plug
  2. Bearer token from Authorization header — manual auth attempt
  3. Demo Tenant fallback — auto-created if missing (dev convenience)
  """

  alias Kalcifer.Repo
  alias Kalcifer.Tenants
  alias Kalcifer.Tenants.Tenant

  @doc "Returns the tenant struct for the current request."
  def resolve(conn) do
    case conn.assigns[:current_tenant] do
      %Tenant{} = tenant ->
        tenant

      _ ->
        case try_auth_header(conn) do
          %Tenant{} = tenant -> tenant
          nil -> get_or_create_demo_tenant()
        end
    end
  end

  @doc "Returns the tenant_id for the current request."
  def resolve_id(conn) do
    resolve(conn).id
  end

  defp try_auth_header(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" ->
        hash = Tenants.hash_api_key(token)
        Tenants.get_tenant_by_api_key_hash(hash)

      _ ->
        nil
    end
  end

  defp get_or_create_demo_tenant do
    case Repo.get_by(Tenant, name: "Demo Tenant") do
      %Tenant{} = tenant ->
        tenant

      nil ->
        {:ok, tenant} =
          Tenants.create_tenant(%{
            name: "Demo Tenant",
            api_key_hash: Tenants.hash_api_key("demo-dev-key")
          })

        tenant
    end
  end
end
