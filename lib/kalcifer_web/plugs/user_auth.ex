defmodule KalciferWeb.Plugs.UserAuth do
  @moduledoc """
  Authenticates requests using session tokens (from Google OAuth flow).

  Extracts Bearer token from Authorization header, verifies it,
  and assigns current_user and current_tenant to conn.

  Falls through silently if no token present (for optional auth).
  """

  import Plug.Conn

  alias Kalcifer.Accounts
  alias Kalcifer.Tenants
  alias KalciferWeb.AuthController

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user_id} <- AuthController.verify_session_token(token),
         %{} = user <- Accounts.get_user(user_id),
         %{} = tenant <- Tenants.get_tenant(user.tenant_id) do
      conn
      |> assign(:current_user, user)
      |> assign(:current_tenant, tenant)
    else
      _ -> conn
    end
  end
end
