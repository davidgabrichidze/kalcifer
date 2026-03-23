defmodule Kalcifer.Engine.Nodes.Action.AI.Helpers do
  @moduledoc false

  @doc """
  Builds a single-message list from a prompt, optionally including
  accumulated context from previous nodes.
  """
  def build_messages(prompt, config, context) do
    include_ctx = Map.get(config, "include_context", true)

    content =
      if include_ctx do
        ctx_summary = summarize_context(context)
        "#{prompt}\n\nContext:\n#{ctx_summary}"
      else
        prompt
      end

    [%{role: "user", content: content}]
  end

  @doc """
  Summarises accumulated results from prior nodes, skipping system fields.
  Returns "(no previous results)" when the map is empty.
  """
  def summarize_context(context) do
    context
    |> Map.get("accumulated", %{})
    |> Enum.map(fn {node_id, result} ->
      "#{node_id}: #{inspect(result, limit: 200)}"
    end)
    |> Enum.join("\n")
    |> case do
      "" -> "(no previous results)"
      summary -> summary
    end
  end

  @doc """
  Interpolates `{{key}}` placeholders in a string using values from context.

  Supports dot notation: `{{accumulated.planner.response}}` walks into
  nested maps.
  """
  def interpolate(template, context) when is_binary(template) do
    Regex.replace(~r/\{\{([^}]+)\}\}/, template, fn _match, path ->
      path
      |> String.split(".")
      |> resolve_path(context)
      |> case do
        nil -> "{{#{path}}}"
        val when is_binary(val) -> val
        val -> inspect(val, limit: 200)
      end
    end)
  end

  def interpolate(nil, _context), do: nil

  defp resolve_path([], value), do: value
  defp resolve_path([key | rest], map) when is_map(map), do: resolve_path(rest, Map.get(map, key))
  defp resolve_path(_keys, _other), do: nil
end
