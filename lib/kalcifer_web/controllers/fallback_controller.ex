defmodule KalciferWeb.FallbackController do
  @moduledoc """
  Renders all controller error tuples in the standard envelope
  (see `KalciferWeb.ErrorResponse`).
  """

  use KalciferWeb, :controller

  alias Kalcifer.Engine.ErrorCatalog
  alias KalciferWeb.ErrorResponse

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
    render_catalog(conn, Map.fetch!(@status_map, code), code)
  end

  def call(conn, {:error, {:invalid_changeset, %Ecto.Changeset{} = changeset}}) do
    render_changeset(conn, changeset)
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    render_changeset(conn, changeset)
  end

  def call(conn, {:error, {:preflight_failed, errors}}) when is_list(errors) do
    ErrorResponse.send_error(
      conn,
      :unprocessable_entity,
      "preflight_failed",
      "Flow preflight validation failed.",
      details: errors
    )
  end

  def call(conn, {:error, {:invalid_params, message}}) when is_binary(message) do
    ErrorResponse.send_error(conn, :bad_request, "invalid_params", message)
  end

  # Catch-all for unhandled error atoms
  def call(conn, {:error, reason}) when is_atom(reason) do
    render_catalog(conn, :internal_server_error, reason)
  end

  defp render_catalog(conn, status, code) do
    info = ErrorCatalog.humanize_code(code)

    ErrorResponse.send_error(conn, status, info.code, info.message, suggestion: info[:suggestion])
  end

  defp render_changeset(conn, changeset) do
    ErrorResponse.send_error(
      conn,
      :unprocessable_entity,
      "validation_failed",
      "Validation failed.",
      details: format_errors(changeset)
    )
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
