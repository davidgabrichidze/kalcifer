defmodule Kalcifer.Engine.Nodes.Action.Data.MemoryRecallTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Action.Data.MemoryRecall

  describe "execute/2 — dry run" do
    test "returns recall metadata" do
      config = %{
        "keys" => ["user_preference", "project_name"],
        "category" => "preference",
        "context_key" => "prefs"
      }

      context = %{"_dry_run" => true, "_tenant_id" => "t1"}

      assert {:completed, %{dry_run: true, would_recall: recall}} =
               MemoryRecall.execute(config, context)

      assert recall.keys == ["user_preference", "project_name"]
      assert recall.category == "preference"
      assert recall.context_key == "prefs"
    end
  end

  describe "config_schema/0" do
    test "defines keys, category, context_key" do
      schema = MemoryRecall.config_schema()
      assert Map.has_key?(schema, "keys")
      assert Map.has_key?(schema, "category")
      assert Map.has_key?(schema, "context_key")
    end
  end

  describe "category/0" do
    test "returns :action" do
      assert MemoryRecall.category() == :action
    end
  end
end
