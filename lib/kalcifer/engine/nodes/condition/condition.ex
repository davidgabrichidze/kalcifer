defmodule Kalcifer.Engine.Nodes.Condition.Condition do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, context) do
    field = config["field"]
    expected = config["value"]
    actual = context[field]

    if actual == expected do
      {:branched, "true", %{matched: true, field: field, expected: expected, actual: actual}}
    else
      {:branched, "false", %{matched: false, field: field, expected: expected, actual: actual}}
    end
  end

  @impl true
  def config_schema do
    %{
      "field" => %{"type" => "string", "required" => true},
      "value" => %{"type" => "any", "required" => true}
    }
  end

  @impl true
  def category, do: :condition
end
