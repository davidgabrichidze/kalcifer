defmodule KalciferWeb.ErrorResponse do
  @moduledoc """
  Single JSON error envelope for the API:

      {"error": "<code>", "code": "<code>", "message": "...", "details": ..., "suggestion": "..."}

  `error` and `code` both carry the machine-readable code string
  (`error` for legacy consumers, `code` per the documented format);
  `message` is always present and human-readable; `details` (structured
  info such as field errors) and `suggestion` are included only when
  available.
  """

  import Plug.Conn

  def send_error(conn, status, code, message, opts \\ []) do
    code = to_string(code)

    payload =
      %{error: code, code: code, message: message}
      |> maybe_put(:details, opts[:details])
      |> maybe_put(:suggestion, opts[:suggestion])

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(payload)
    |> halt()
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
