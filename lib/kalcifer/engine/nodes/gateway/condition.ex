defmodule Kalcifer.Engine.Nodes.Gateway.Condition do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, context) do
    field = config["field"]
    value = config["value"]
    actual = get_in(context, access_path(field))

    if actual == value do
      {:branched, "true", %{field: field, matched: true}}
    else
      {:branched, "false", %{field: field, matched: false}}
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
  def category, do: :gateway

  defp access_path(field) when is_binary(field) do
    String.split(field, ".")
  end

  defp access_path(_), do: []
end
