defmodule Kalcifer.Engine.Nodes.Condition.AbSplit do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    variants = config["variants"] || []
    selected = weighted_random(variants)
    key = selected["key"]
    {:branched, key, %{selected_variant: key}}
  end

  @impl true
  def config_schema do
    %{
      "variants" => %{
        "type" => "array",
        "required" => true,
        "items" => %{
          "key" => %{"type" => "string"},
          "weight" => %{"type" => "integer"}
        }
      }
    }
  end

  @impl true
  def category, do: :condition

  defp weighted_random(variants) do
    total = Enum.reduce(variants, 0, fn v, acc -> acc + (v["weight"] || 1) end)
    roll = :rand.uniform(total)
    pick(variants, roll, 0)
  end

  defp pick([variant | rest], roll, acc) do
    acc = acc + (variant["weight"] || 1)
    if roll <= acc, do: variant, else: pick(rest, roll, acc)
  end

  defp pick([], _roll, _acc), do: nil
end
