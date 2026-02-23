defmodule Kalcifer.Customers.SegmentEvaluatorTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Customers.SegmentEvaluator

  defp customer(overrides \\ %{}) do
    Map.merge(
      %{
        email: "alice@example.com",
        phone: "+15551234567",
        name: "Alice",
        properties: %{"plan" => "premium", "age" => 30, "city" => "Tbilisi"},
        tags: ["vip", "active"]
      },
      overrides
    )
  end

  defp segment(rules) do
    %{rules: rules}
  end

  describe "member?/2" do
    test "matches eq operator" do
      seg = segment([%{"field" => "plan", "operator" => "eq", "value" => "premium"}])
      assert SegmentEvaluator.member?(customer(), seg)
    end

    test "rejects eq when not matching" do
      seg = segment([%{"field" => "plan", "operator" => "eq", "value" => "free"}])
      refute SegmentEvaluator.member?(customer(), seg)
    end

    test "matches neq operator" do
      seg = segment([%{"field" => "plan", "operator" => "neq", "value" => "free"}])
      assert SegmentEvaluator.member?(customer(), seg)
    end

    test "matches gt operator on numbers" do
      seg = segment([%{"field" => "age", "operator" => "gt", "value" => 25}])
      assert SegmentEvaluator.member?(customer(), seg)
    end

    test "matches lt operator on numbers" do
      seg = segment([%{"field" => "age", "operator" => "lt", "value" => 40}])
      assert SegmentEvaluator.member?(customer(), seg)
    end

    test "matches contains on string" do
      seg = segment([%{"field" => "email", "operator" => "contains", "value" => "example"}])
      assert SegmentEvaluator.member?(customer(), seg)
    end

    test "matches contains on tags list" do
      seg = segment([%{"field" => "tags", "operator" => "contains", "value" => "vip"}])
      assert SegmentEvaluator.member?(customer(), seg)
    end

    test "matches in operator" do
      seg = segment([%{"field" => "city", "operator" => "in", "value" => ["Tbilisi", "Batumi"]}])
      assert SegmentEvaluator.member?(customer(), seg)
    end

    test "matches not_in operator" do
      seg =
        segment([%{"field" => "city", "operator" => "not_in", "value" => ["Paris", "London"]}])

      assert SegmentEvaluator.member?(customer(), seg)
    end

    test "all rules must match (AND logic)" do
      seg =
        segment([
          %{"field" => "plan", "operator" => "eq", "value" => "premium"},
          %{"field" => "age", "operator" => "gt", "value" => 50}
        ])

      refute SegmentEvaluator.member?(customer(), seg)
    end

    test "empty rules means all customers match" do
      seg = segment([])
      assert SegmentEvaluator.member?(customer(), seg)
    end
  end
end
