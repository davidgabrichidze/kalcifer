defmodule KalciferWeb.Plugs.ApiKeyAuth do
  @moduledoc false

  import Plug.Conn

  alias Kalcifer.Tenants

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, raw_key} <- extract_token(conn),
         hash = Tenants.hash_api_key(raw_key),
         %{} = tenant <- Tenants.get_tenant_by_api_key_hash(hash) do
      assign(conn, :current_tenant, tenant)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "invalid_api_key"})
        |> halt()
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> :error
    end
  end
end
