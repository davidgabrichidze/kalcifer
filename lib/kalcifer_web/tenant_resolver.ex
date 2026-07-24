defmodule KalciferWeb.TenantResolver do
  @moduledoc """
  Shared tenant resolution for controllers that serve both API-key callers
  and the operator frontend (Google session tokens).

  Resolution order:
  1. `conn.assigns[:current_tenant]` — set by ApiKeyAuth, UserAuth or ResolveTenant
  2. Bearer token from Authorization header — manual API-key auth attempt
  3. `x-tenant-id` header — dev frontend tenant switching
  4. Demo Tenant fallback — dev/test convenience, auto-created if missing

  Steps 3 and 4 are gated on `:allow_tenant_header` (dev/test only). In
  production an unauthenticated request resolves to no tenant at all, and
  `KalciferWeb.Plugs.ResolveTenant` turns that into a 401 before any
  controller runs.
  """

  alias Kalcifer.Repo
  alias Kalcifer.Tenants
  alias Kalcifer.Tenants.Tenant

  @doc """
  Returns the tenant for the current request, or nil when none can be
  resolved. Prefer this in plugs and anywhere a missing tenant is a normal
  outcome rather than a bug.
  """
  def resolve_or_nil(conn) do
    with nil <- assigned_tenant(conn),
         nil <- try_auth_header(conn),
         nil <- try_tenant_header(conn) do
      demo_tenant()
    end
  end

  @doc """
  Returns the tenant struct for the current request.

  Raises when no tenant can be resolved. Routes that reach a controller must
  pipe through `KalciferWeb.Plugs.ResolveTenant` or `ApiKeyAuth`, either of
  which assigns the tenant (or halts) first — so a raise here means the
  pipeline is misconfigured, not that a caller sent a bad request.
  """
  def resolve(conn) do
    resolve_or_nil(conn) || raise_unresolved()
  end

  @doc "Returns the tenant_id for the current request."
  def resolve_id(conn) do
    resolve(conn).id
  end

  defp assigned_tenant(conn) do
    case conn.assigns[:current_tenant] do
      %Tenant{} = tenant -> tenant
      _ -> nil
    end
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

  # The x-tenant-id header lets a caller pick any tenant, which is only safe
  # for the local dev frontend. Disabled in production so it can never be used
  # to assume another tenant; there, resolution requires a real Bearer token.
  defp try_tenant_header(conn) do
    if dev_frontend?() do
      with [id] when id != "" <- Plug.Conn.get_req_header(conn, "x-tenant-id"),
           {:ok, _uuid} <- Ecto.UUID.cast(id) do
        Repo.get(Tenant, id)
      else
        _ -> nil
      end
    end
  end

  # Auto-creating a tenant for an anonymous caller is a dev affordance: it
  # keeps the frontend usable before anyone logs in. In production it would
  # hand every unauthenticated request read and write access to one shared
  # tenant, so it is gated on the same flag as the x-tenant-id header.
  defp demo_tenant do
    if dev_frontend?() do
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

  defp dev_frontend?, do: Application.get_env(:kalcifer, :allow_tenant_header, false)

  defp raise_unresolved do
    raise "no tenant on the connection — this route must pipe through " <>
            "KalciferWeb.Plugs.ResolveTenant or KalciferWeb.Plugs.ApiKeyAuth"
  end
end
