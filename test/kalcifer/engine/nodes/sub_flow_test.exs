defmodule Kalcifer.Engine.Nodes.Action.SubFlowTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Action.SubFlow

  describe "execute/2 — dry run" do
    test "returns sub-flow metadata" do
      config = %{
        "flow_id" => Ecto.UUID.generate(),
        "context_mapping" => %{"user_name" => "name"}
      }

      context = %{"_dry_run" => true, "user_name" => "David"}

      assert {:completed, %{dry_run: true, sub_flow: sub}} =
               SubFlow.execute(config, context)

      assert sub.flow_id == config["flow_id"]
      assert sub.would_execute == true
    end
  end

  describe "validate/1" do
    test "accepts valid config" do
      assert :ok = SubFlow.validate(%{"flow_id" => Ecto.UUID.generate()})
    end

    test "rejects missing flow_id" do
      assert {:error, ["flow_id is required"]} = SubFlow.validate(%{})
    end

    test "rejects empty flow_id" do
      assert {:error, ["flow_id is required"]} = SubFlow.validate(%{"flow_id" => ""})
    end
  end

  describe "config_schema/0" do
    test "defines flow_id, context_mapping, wait, timeout" do
      schema = SubFlow.config_schema()
      assert Map.has_key?(schema, "flow_id")
      assert Map.has_key?(schema, "context_mapping")
      assert Map.has_key?(schema, "wait")
      assert Map.has_key?(schema, "timeout_ms")
    end
  end

  describe "category/0" do
    test "returns :action" do
      assert SubFlow.category() == :action
    end
  end
end
