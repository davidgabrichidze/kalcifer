defmodule KalciferWeb.CacheBodyReader do
  @moduledoc """
  Plug.Parsers body reader that caches the raw request body in
  `conn.assigns.raw_body` for webhook endpoints, where signature
  verification must run over the exact bytes the provider sent.
  """

  @cached_prefix "/api/v1/webhooks/"

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, chunk, conn} -> {:ok, chunk, maybe_cache(conn, chunk)}
      {:more, chunk, conn} -> {:more, chunk, maybe_cache(conn, chunk)}
      other -> other
    end
  end

  defp maybe_cache(conn, chunk) do
    if String.starts_with?(conn.request_path, @cached_prefix) do
      Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> chunk)
    else
      conn
    end
  end
end
