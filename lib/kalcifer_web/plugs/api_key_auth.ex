defmodule KalciferWeb.Plugs.ApiKeyAuth do
  @moduledoc false

  import Plug.Conn

  require Logger

  alias Kalcifer.Tenants

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, raw_key} <- extract_token(conn),
         hash = Tenants.hash_api_key(raw_key),
         %{} = tenant <- Tenants.get_tenant_by_api_key_hash(hash) do
      Logger.metadata(tenant_id: tenant.id)
      assign(conn, :current_tenant, tenant)
    else
      _ ->
        KalciferWeb.ErrorResponse.send_error(
          conn,
          :unauthorized,
          "invalid_api_key",
          "Invalid or missing API key. Pass it as 'Authorization: Bearer <key>'."
        )
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> :error
    end
  end
end
