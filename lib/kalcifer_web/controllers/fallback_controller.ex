defmodule KalciferWeb.FallbackController do
  use KalciferWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found"})
  end

  def call(conn, {:error, :not_draft}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "flow_not_draft"})
  end

  def call(conn, {:error, :no_draft_version}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "no_draft_version"})
  end

  def call(conn, {:error, :flow_not_active}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "flow_not_active"})
  end

  def call(conn, {:error, :no_active_version}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "no_active_version"})
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors = format_errors(changeset)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
