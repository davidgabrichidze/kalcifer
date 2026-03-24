defmodule Kalcifer.Engine.Nodes.Action.AI.FlowRouterTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Action.AI.FlowRouter

  describe "execute/2 — dry run" do
    test "picks first route in dry run" do
      config = %{
        "question" => "Simple or complex?",
        "routes" => %{
          "simple" => "flow-uuid-1",
          "complex" => "flow-uuid-2"
        }
      }

      assert {:branched, "complex", result} = FlowRouter.execute(config, %{"_dry_run" => true})
      # Map key ordering — just check it chose one of the routes
      assert result.dry_run == true
      assert result.flow_id in ["flow-uuid-1", "flow-uuid-2"]
    end
  end

  describe "validate/1" do
    test "accepts valid config" do
      config = %{
        "question" => "Which path?",
        "routes" => %{"a" => "flow-1", "b" => "flow-2"}
      }

      assert :ok = FlowRouter.validate(config)
    end

    test "rejects missing question" do
      config = %{"routes" => %{"a" => "1", "b" => "2"}}
      assert {:error, errors} = FlowRouter.validate(config)
      assert Enum.any?(errors, &String.contains?(&1, "question"))
    end

    test "rejects fewer than 2 routes" do
      config = %{"question" => "x", "routes" => %{"only" => "1"}}
      assert {:error, errors} = FlowRouter.validate(config)
      assert Enum.any?(errors, &String.contains?(&1, "routes"))
    end
  end

  describe "category/0" do
    test "returns :condition" do
      assert FlowRouter.category() == :condition
    end
  end
end
