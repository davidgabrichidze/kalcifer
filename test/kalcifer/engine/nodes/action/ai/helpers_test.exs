defmodule Kalcifer.Engine.Nodes.Action.AI.HelpersTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Action.AI.Helpers

  describe "interpolate/2" do
    test "replaces simple {{key}} placeholders" do
      assert "Hello world" == Helpers.interpolate("Hello {{name}}", %{"name" => "world"})
    end

    test "replaces dot-notation paths" do
      context = %{"accumulated" => %{"planner" => %{"response" => "Build it"}}}
      assert "Plan: Build it" == Helpers.interpolate("Plan: {{accumulated.planner.response}}", context)
    end

    test "leaves unresolved placeholders as-is" do
      assert "Hello {{missing}}" == Helpers.interpolate("Hello {{missing}}", %{})
    end

    test "handles nil template" do
      assert nil == Helpers.interpolate(nil, %{})
    end

    test "converts non-string values to inspect format" do
      assert result = Helpers.interpolate("Count: {{count}}", %{"count" => 42})
      assert result == "Count: 42"
    end
  end

  describe "summarize_context/1" do
    test "formats accumulated results" do
      context = %{"accumulated" => %{"node1" => %{response: "Hello"}, "node2" => %{value: 42}}}
      summary = Helpers.summarize_context(context)
      assert summary =~ "node1:"
      assert summary =~ "node2:"
    end

    test "returns placeholder for empty context" do
      assert "(no previous results)" == Helpers.summarize_context(%{})
      assert "(no previous results)" == Helpers.summarize_context(%{"accumulated" => %{}})
    end
  end

  describe "build_messages/3" do
    test "creates a single user message with prompt" do
      messages = Helpers.build_messages("Analyze this", %{"include_context" => false}, %{})
      assert [%{role: "user", content: "Analyze this"}] = messages
    end

    test "includes context when include_context is true" do
      context = %{"accumulated" => %{"step1" => %{data: "test"}}}
      messages = Helpers.build_messages("Analyze", %{"include_context" => true}, context)
      assert [%{role: "user", content: content}] = messages
      assert content =~ "Analyze"
      assert content =~ "Context:"
      assert content =~ "step1:"
    end

    test "defaults to including context" do
      context = %{"accumulated" => %{"step1" => "data"}}
      messages = Helpers.build_messages("Prompt", %{}, context)
      assert [%{content: content}] = messages
      assert content =~ "Context:"
    end
  end
end
