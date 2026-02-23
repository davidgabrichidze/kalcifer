defmodule Kalcifer.Bugs.AbSplitEmptyVariantsTest do
  @moduledoc """
  N4: AbSplit.weighted_random crashes with :rand.uniform(0) when variants list is empty.
  Every customer hitting this node fails the instance.
  """
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Condition.AbSplit

  @tag :known_bug
  test "execute with empty variants should return error, not crash" do
    config = %{"variants" => []}

    # BUG: :rand.uniform(0) raises FunctionClauseError
    # Should return {:failed, :no_variants} or similar
    assert_raise FunctionClauseError, fn ->
      AbSplit.execute(config, %{})
    end
  end

  @tag :known_bug
  test "execute with missing variants key should return error, not crash" do
    config = %{}

    assert_raise FunctionClauseError, fn ->
      AbSplit.execute(config, %{})
    end
  end
end
