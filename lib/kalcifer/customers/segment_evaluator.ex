defmodule Kalcifer.Customers.SegmentEvaluator do
  @moduledoc false

  def member?(customer, segment) do
    Enum.all?(segment.rules, &evaluate_rule(&1, customer))
  end

  defp evaluate_rule(%{"field" => field, "operator" => op, "value" => value}, customer) do
    actual = get_field(customer, field)
    compare(op, actual, value)
  end

  defp evaluate_rule(_, _customer), do: false

  defp get_field(customer, "email"), do: customer.email
  defp get_field(customer, "phone"), do: customer.phone
  defp get_field(customer, "name"), do: customer.name

  defp get_field(customer, "tags"), do: customer.tags

  defp get_field(customer, field) do
    Map.get(customer.properties, field)
  end

  defp compare("eq", actual, value), do: actual == value
  defp compare("neq", actual, value), do: actual != value

  defp compare("gt", actual, value) when is_number(actual) and is_number(value),
    do: actual > value

  defp compare("lt", actual, value) when is_number(actual) and is_number(value),
    do: actual < value

  defp compare("contains", actual, value) when is_binary(actual),
    do: String.contains?(actual, value)

  defp compare("contains", actual, value) when is_list(actual), do: value in actual
  defp compare("in", actual, values) when is_list(values), do: actual in values
  defp compare("not_in", actual, values) when is_list(values), do: actual not in values
  defp compare(_, _, _), do: false
end
