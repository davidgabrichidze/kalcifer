defmodule Kalcifer.Customers.SegmentQuery do
  @moduledoc """
  Builds Ecto queries for dynamic segment membership so segments are
  evaluated at the database level (member listing/counting), with the
  same semantics as the in-memory `SegmentEvaluator` used for a single
  already-loaded customer.

  All rules are ANDed. Unknown fields are looked up in the `properties`
  JSONB column; `email`/`phone`/`name` hit their columns and `tags` the
  array column. Rules with unknown operators match nothing.
  """

  import Ecto.Query

  alias Kalcifer.Customers.Customer

  @top_level_fields ~w(email phone name)

  def members_query(segment) do
    base = from(c in Customer, where: c.tenant_id == ^segment.tenant_id)

    Enum.reduce(segment.rules, base, fn rule, query ->
      where(query, ^rule_condition(rule))
    end)
  end

  defp rule_condition(%{"field" => field, "operator" => op} = rule) do
    condition(field, op, rule["value"])
  end

  defp rule_condition(_rule), do: dynamic(false)

  defp condition("tags", op, value) do
    case op do
      # Array containment (@>) rather than `value = ANY(tags)` so the query
      # can use the GIN index on tags; the two are equivalent for one value.
      "contains" when is_binary(value) ->
        dynamic([c], fragment("? @> ?", c.tags, ^[value]))

      "eq" when is_list(value) ->
        dynamic([c], c.tags == ^value)

      # The tags column defaults to [] and is never NULL
      "exists" ->
        dynamic(true)

      "not_exists" ->
        dynamic(false)

      _ ->
        dynamic(false)
    end
  end

  defp condition(field, op, value) when field in @top_level_fields do
    column_condition(String.to_existing_atom(field), op, value)
  end

  defp condition(field, op, value), do: property_condition(field, op, value)

  defp column_condition(fa, "eq", value), do: dynamic([c], field(c, ^fa) == ^value)

  # NULL != 'x' is NULL in SQL; in-memory nil != value is true
  defp column_condition(fa, "neq", value),
    do: dynamic([c], field(c, ^fa) != ^value or is_nil(field(c, ^fa)))

  defp column_condition(fa, "contains", value) when is_binary(value),
    do: dynamic([c], like(field(c, ^fa), ^contains_pattern(value)))

  defp column_condition(fa, "in", value) when is_list(value),
    do: dynamic([c], field(c, ^fa) in ^value)

  defp column_condition(fa, "not_in", value) when is_list(value),
    do: dynamic([c], field(c, ^fa) not in ^value or is_nil(field(c, ^fa)))

  defp column_condition(fa, "exists", _value), do: dynamic([c], not is_nil(field(c, ^fa)))

  defp column_condition(fa, "not_exists", _value), do: dynamic([c], is_nil(field(c, ^fa)))

  defp column_condition(_fa, _op, _value), do: dynamic(false)

  defp property_condition(field, "eq", value),
    do: dynamic([c], fragment("? @> ?", c.properties, ^%{field => value}))

  defp property_condition(field, "neq", value),
    do: dynamic([c], not fragment("? @> ?", c.properties, ^%{field => value}))

  defp property_condition(field, "gt", value) when is_number(value) do
    dynamic(
      [c],
      fragment(
        "(jsonb_typeof(? -> ?) = 'number' AND (? ->> ?)::numeric > ?)",
        c.properties,
        ^field,
        c.properties,
        ^field,
        ^value
      )
    )
  end

  defp property_condition(field, "lt", value) when is_number(value) do
    dynamic(
      [c],
      fragment(
        "(jsonb_typeof(? -> ?) = 'number' AND (? ->> ?)::numeric < ?)",
        c.properties,
        ^field,
        c.properties,
        ^field,
        ^value
      )
    )
  end

  defp property_condition(field, "contains", value) when is_binary(value) do
    dynamic(
      [c],
      fragment(
        "((jsonb_typeof(? -> ?) = 'string' AND ? ->> ? LIKE ?) OR (jsonb_typeof(? -> ?) = 'array' AND ? -> ? @> ?))",
        c.properties,
        ^field,
        c.properties,
        ^field,
        ^contains_pattern(value),
        c.properties,
        ^field,
        c.properties,
        ^field,
        ^[value]
      )
    )
  end

  defp property_condition(field, "in", value) when is_list(value) do
    dynamic(
      [c],
      fragment("? ->> ? = ANY(?)", c.properties, ^field, ^Enum.map(value, &to_string/1))
    )
  end

  # in-memory: nil not in values is true, so include missing fields
  defp property_condition(field, "not_in", value) when is_list(value) do
    dynamic(
      [c],
      fragment(
        "((? ->> ?) IS NULL OR NOT (? ->> ? = ANY(?)))",
        c.properties,
        ^field,
        c.properties,
        ^field,
        ^Enum.map(value, &to_string/1)
      )
    )
  end

  defp property_condition(field, "exists", _value),
    do: dynamic([c], fragment("jsonb_exists(?, ?)", c.properties, ^field))

  defp property_condition(field, "not_exists", _value),
    do: dynamic([c], not fragment("jsonb_exists(?, ?)", c.properties, ^field))

  defp property_condition(_field, _op, _value), do: dynamic(false)

  defp contains_pattern(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%" <> escaped <> "%"
  end
end
