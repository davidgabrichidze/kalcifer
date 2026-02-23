defmodule Kalcifer.Bugs.AbSplitEmptyVariantsTest do
  @moduledoc """
  N4: AbSplit previously crashed with :rand.uniform(0) when variants list was
  empty. Fixed to return {:failed, :no_variants}.
  """
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Condition.AbSplit

  test "execute with empty variants returns error" do
    config = %{"variants" => []}
    assert {:failed, :no_variants} = AbSplit.execute(config, %{})
  end

  test "execute with missing variants key returns error" do
    config = %{}
    assert {:failed, :no_variants} = AbSplit.execute(config, %{})
  end
end
