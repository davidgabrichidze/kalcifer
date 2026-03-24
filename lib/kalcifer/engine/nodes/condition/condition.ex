defmodule Kalcifer.Engine.Nodes.Condition.Condition do
  @moduledoc """
  General-purpose condition node with operator support.

  Config:
    - field: context key to check (e.g. "email_opened", "age", "plan")
    - operator: comparison operator (default: "equals")
    - value: expected value to compare against

  Operators:
    - equals: field == value
    - not_equals: field != value
    - greater_than: field > value
    - less_than: field < value
    - contains: String.contains?(field, value)
    - not_contains: !String.contains?(field, value)
    - exists: field is present and non-nil
    - not_exists: field is nil or absent
    - in: field in value (value must be a list)
    - matches: Regex.match?(value, field)

  Natural language examples for AI:
    "თუ მომხმარებლის ასაკი 18-ზე მეტია" → field: "age", operator: "greater_than", value: 18
    "თუ გეგმა premium-ია" → field: "plan", operator: "equals", value: "premium"
    "თუ ემაილი მოიცავს @gmail-ს" → field: "email", operator: "contains", value: "@gmail"
    "თუ ტელეფონი მითითებულია" → field: "phone", operator: "exists"
  """

  use Kalcifer.Engine.NodeBehaviour

  @operators ~w(equals not_equals greater_than less_than contains not_contains exists not_exists in matches)

  @impl true
  def execute(config, context) do
    field = config["field"]
    operator = config["operator"] || "equals"
    expected = config["value"]
    actual = context[field]

    matched = evaluate(operator, actual, expected)

    result = %{
      matched: matched,
      field: field,
      operator: operator,
      expected: expected,
      actual: actual
    }

    if matched do
      {:branched, "true", result}
    else
      {:branched, "false", result}
    end
  end

  @impl true
  def config_schema do
    %{
      "field" => %{"type" => "string", "required" => true},
      "operator" => %{
        "type" => "string",
        "enum" => @operators,
        "default" => "equals",
        "description" => "Comparison operator"
      },
      "value" => %{"type" => "any", "required" => false}
    }
  end

  @impl true
  def category, do: :condition

  # ── Operator evaluation ──────────────────────────────

  defp evaluate("equals", actual, expected), do: actual == expected
  defp evaluate("not_equals", actual, expected), do: actual != expected

  defp evaluate("greater_than", actual, expected)
       when is_number(actual) and is_number(expected),
       do: actual > expected

  defp evaluate("greater_than", _, _), do: false

  defp evaluate("less_than", actual, expected)
       when is_number(actual) and is_number(expected),
       do: actual < expected

  defp evaluate("less_than", _, _), do: false

  defp evaluate("contains", actual, expected)
       when is_binary(actual) and is_binary(expected),
       do: String.contains?(actual, expected)

  defp evaluate("contains", _, _), do: false

  defp evaluate("not_contains", actual, expected)
       when is_binary(actual) and is_binary(expected),
       do: not String.contains?(actual, expected)

  defp evaluate("not_contains", _, _), do: true

  defp evaluate("exists", actual, _expected), do: actual != nil
  defp evaluate("not_exists", actual, _expected), do: actual == nil

  defp evaluate("in", actual, expected) when is_list(expected), do: actual in expected
  defp evaluate("in", _, _), do: false

  defp evaluate("matches", actual, expected)
       when is_binary(actual) and is_binary(expected) do
    case Regex.compile(expected) do
      {:ok, regex} -> Regex.match?(regex, actual)
      _ -> false
    end
  end

  defp evaluate("matches", _, _), do: false

  # Unknown operator — fall back to equals
  defp evaluate(_, actual, expected), do: actual == expected
end
