defmodule Kalcifer.Engine.Nodes.Condition.ConditionTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Condition.Condition

  describe "execute/2 — equals (default)" do
    test "branches true when field matches value" do
      config = %{"field" => "plan", "value" => "premium"}
      context = %{"plan" => "premium"}
      assert {:branched, "true", %{matched: true}} = Condition.execute(config, context)
    end

    test "branches false when field does not match" do
      config = %{"field" => "plan", "value" => "premium"}
      context = %{"plan" => "free"}
      assert {:branched, "false", %{matched: false}} = Condition.execute(config, context)
    end

    test "defaults to equals when operator omitted" do
      config = %{"field" => "status", "value" => "active"}
      context = %{"status" => "active"}
      assert {:branched, "true", %{operator: "equals"}} = Condition.execute(config, context)
    end
  end

  describe "execute/2 — not_equals" do
    test "branches true when field differs" do
      config = %{"field" => "plan", "operator" => "not_equals", "value" => "free"}
      context = %{"plan" => "premium"}
      assert {:branched, "true", _} = Condition.execute(config, context)
    end
  end

  describe "execute/2 — greater_than / less_than" do
    test "greater_than with numeric values" do
      config = %{"field" => "age", "operator" => "greater_than", "value" => 18}
      assert {:branched, "true", _} = Condition.execute(config, %{"age" => 25})
      assert {:branched, "false", _} = Condition.execute(config, %{"age" => 16})
    end

    test "less_than with numeric values" do
      config = %{"field" => "score", "operator" => "less_than", "value" => 50}
      assert {:branched, "true", _} = Condition.execute(config, %{"score" => 30})
      assert {:branched, "false", _} = Condition.execute(config, %{"score" => 80})
    end

    test "greater_than returns false for non-numeric" do
      config = %{"field" => "age", "operator" => "greater_than", "value" => 18}
      assert {:branched, "false", _} = Condition.execute(config, %{"age" => "old"})
    end
  end

  describe "execute/2 — contains / not_contains" do
    test "contains matches substring" do
      config = %{"field" => "email", "operator" => "contains", "value" => "@gmail"}
      assert {:branched, "true", _} = Condition.execute(config, %{"email" => "user@gmail.com"})
      assert {:branched, "false", _} = Condition.execute(config, %{"email" => "user@yahoo.com"})
    end

    test "not_contains inverts" do
      config = %{"field" => "email", "operator" => "not_contains", "value" => "spam"}
      assert {:branched, "true", _} = Condition.execute(config, %{"email" => "user@gmail.com"})
    end
  end

  describe "execute/2 — exists / not_exists" do
    test "exists checks for non-nil" do
      config = %{"field" => "phone", "operator" => "exists"}
      assert {:branched, "true", _} = Condition.execute(config, %{"phone" => "+995555"})
      assert {:branched, "false", _} = Condition.execute(config, %{"phone" => nil})
      assert {:branched, "false", _} = Condition.execute(config, %{})
    end

    test "not_exists checks for nil/absent" do
      config = %{"field" => "phone", "operator" => "not_exists"}
      assert {:branched, "true", _} = Condition.execute(config, %{})
      assert {:branched, "false", _} = Condition.execute(config, %{"phone" => "+995555"})
    end
  end

  describe "execute/2 — in" do
    test "checks membership in list" do
      config = %{"field" => "country", "operator" => "in", "value" => ["GE", "AM", "AZ"]}
      assert {:branched, "true", _} = Condition.execute(config, %{"country" => "GE"})
      assert {:branched, "false", _} = Condition.execute(config, %{"country" => "US"})
    end
  end

  describe "execute/2 — matches (regex)" do
    test "matches regex pattern" do
      config = %{"field" => "email", "operator" => "matches", "value" => "^[a-z]+@"}
      assert {:branched, "true", _} = Condition.execute(config, %{"email" => "user@test.com"})
      assert {:branched, "false", _} = Condition.execute(config, %{"email" => "123@test.com"})
    end

    test "invalid regex returns false" do
      config = %{"field" => "email", "operator" => "matches", "value" => "[invalid"}
      assert {:branched, "false", _} = Condition.execute(config, %{"email" => "test"})
    end
  end

  describe "config_schema/0" do
    test "includes field, operator, and value" do
      schema = Condition.config_schema()
      assert Map.has_key?(schema, "field")
      assert Map.has_key?(schema, "operator")
      assert Map.has_key?(schema, "value")
      assert "equals" in schema["operator"]["enum"]
      assert "greater_than" in schema["operator"]["enum"]
      assert "contains" in schema["operator"]["enum"]
    end
  end

  describe "category/0" do
    test "returns :condition" do
      assert Condition.category() == :condition
    end
  end
end
