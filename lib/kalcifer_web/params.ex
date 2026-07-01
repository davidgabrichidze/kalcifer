defmodule KalciferWeb.Params do
  @moduledoc """
  Request-parameter validation on top of NimbleOptions.

  Controllers declare a NimbleOptions-style schema; `validate/2` picks
  the declared keys from the raw string-keyed params map, validates,
  and returns an atom-keyed map (unknown params are ignored). Failures
  return `{:error, {:invalid_params, message}}`, rendered by the
  FallbackController as 400 `invalid_params`.
  """

  def validate(params, schema) when is_map(params) and is_list(schema) do
    picked =
      for key <- Keyword.keys(schema),
          {:ok, value} <- [Map.fetch(params, Atom.to_string(key))],
          do: {key, value}

    case NimbleOptions.validate(picked, schema) do
      {:ok, validated} ->
        {:ok, Map.new(validated)}

      {:error, %NimbleOptions.ValidationError{message: message}} ->
        {:error, {:invalid_params, message}}
    end
  end

  @doc "Shared limit/offset schema for paginated index endpoints."
  def pagination_schema do
    [
      limit: [type: {:custom, __MODULE__, :int_param, [[min: 1, max: 200]]}, default: 50],
      offset: [type: {:custom, __MODULE__, :int_param, [[min: 0]]}, default: 0]
    ]
  end

  @doc "NimbleOptions custom type: any map (JSON object with string keys)."
  def json_map(value) when is_map(value), do: {:ok, value}
  def json_map(_value), do: {:error, "must be a map"}

  @doc "NimbleOptions custom type: non-empty string."
  def non_empty_string(value) when is_binary(value) and value != "", do: {:ok, value}
  def non_empty_string(_value), do: {:error, "must be a non-empty string"}

  @doc "NimbleOptions custom type: integer (or numeric string) with bounds."
  def int_param(value, bounds) do
    with {:ok, int} <- parse_int(value) do
      min = Keyword.get(bounds, :min)
      max = Keyword.get(bounds, :max)

      cond do
        min && int < min -> {:error, "must be greater than or equal to #{min}"}
        max && int > max -> {:error, "must be less than or equal to #{max}"}
        true -> {:ok, int}
      end
    end
  end

  defp parse_int(value) when is_integer(value), do: {:ok, value}

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "must be an integer"}
    end
  end

  defp parse_int(_value), do: {:error, "must be an integer"}
end
