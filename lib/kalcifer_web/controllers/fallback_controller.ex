defmodule KalciferWeb.FallbackController do
  use KalciferWeb, :controller

  alias Kalcifer.Engine.ErrorCatalog

  @status_map %{
    not_found: :not_found,
    version_not_found: :not_found,
    not_draft: :unprocessable_entity,
    journey_not_draft: :unprocessable_entity,
    no_draft_version: :unprocessable_entity,
    flow_not_active: :unprocessable_entity,
    no_active_version: :unprocessable_entity,
    version_not_publishable: :unprocessable_entity,
    invalid_strategy: :unprocessable_entity,
    invalid_version: :unprocessable_entity,
    same_version: :unprocessable_entity,
    already_in_flow: :conflict,
    frequency_cap_exceeded: :too_many_requests
  }

  def call(conn, {:error, code}) when is_atom(code) and is_map_key(@status_map, code) do
    status = Map.fetch!(@status_map, code)
    info = ErrorCatalog.humanize_code(code)

    conn
    |> put_status(status)
    |> json(info)
  end

  def call(conn, {:error, {:invalid_changeset, %Ecto.Changeset{} = changeset}}) do
    errors = format_errors(changeset)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors = format_errors(changeset)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  def call(conn, {:error, {:preflight_failed, errors}}) when is_list(errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "preflight_failed", details: errors})
  end

  # Catch-all for unhandled error atoms
  def call(conn, {:error, reason}) when is_atom(reason) do
    info = ErrorCatalog.humanize_code(reason)

    conn
    |> put_status(:internal_server_error)
    |> json(info)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
