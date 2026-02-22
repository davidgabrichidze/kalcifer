defmodule Kalcifer.Engine.Nodes.Logic.AbSplit do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    variants = config["variants"] || []
    selected = weighted_random(variants)

    case selected do
      nil -> {:failed, :no_variants}
      variant -> {:branched, variant["key"], %{selected_variant: variant["key"]}}
    end
  end

  @impl true
  def config_schema do
    %{
      "variants" => %{
        "type" => "array",
        "items" => %{
          "key" => %{"type" => "string"},
          "weight" => %{"type" => "integer"}
        }
      }
    }
  end

  @impl true
  def category, do: :gateway

  defp weighted_random([]), do: nil

  defp weighted_random(variants) do
    total = Enum.reduce(variants, 0, fn v, acc -> acc + (v["weight"] || 0) end)

    if total <= 0 do
      Enum.random(variants)
    else
      roll = :rand.uniform(total)
      pick_variant(variants, roll, 0)
    end
  end

  defp pick_variant([variant | rest], roll, cumulative) do
    cumulative = cumulative + (variant["weight"] || 0)

    if roll <= cumulative do
      variant
    else
      pick_variant(rest, roll, cumulative)
    end
  end

  defp pick_variant([], _roll, _cumulative), do: nil
end
