defmodule Kalcifer.Bugs.NestedConditionNilTest do
  @moduledoc """
  BUG-028: Null pointer in nested condition field access.

  When condition config has field "props.x.y" and the context has
  props.x = nil, the condition node should handle it gracefully
  (branch false) instead of crashing.
  """
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Condition.Condition

  describe "BUG-028: nested nil field access" do
    test "dotted field path where intermediate is nil returns false, not crash" do
      config = %{
        "field" => "customer.address.city",
        "operator" => "equals",
        "value" => "Tbilisi"
      }

      # Flat key lookup — context["customer.address.city"] is nil
      context = %{"customer" => %{"address" => nil}}

      assert {:branched, "false", _} = Condition.execute(config, context)
    end

    test "completely missing nested field returns false" do
      config = %{
        "field" => "deep.nested.field",
        "operator" => "equals",
        "value" => "anything"
      }

      context = %{}

      assert {:branched, "false", _} = Condition.execute(config, context)
    end

    test "nil context value with contains operator does not crash" do
      config = %{
        "field" => "tags",
        "operator" => "contains",
        "value" => "vip"
      }

      context = %{"tags" => nil}

      # contains on nil should return false, not crash
      assert {:branched, "false", _} = Condition.execute(config, context)
    end

    test "nil context value with greater_than does not crash" do
      config = %{
        "field" => "score",
        "operator" => "greater_than",
        "value" => 10
      }

      context = %{"score" => nil}

      assert {:branched, "false", _} = Condition.execute(config, context)
    end

    test "nil context value with in operator does not crash" do
      config = %{
        "field" => "country",
        "operator" => "in",
        "value" => ["GE", "US"]
      }

      context = %{"country" => nil}

      assert {:branched, "false", _} = Condition.execute(config, context)
    end
  end
end
