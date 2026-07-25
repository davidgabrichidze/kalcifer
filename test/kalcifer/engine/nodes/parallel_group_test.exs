defmodule Kalcifer.Engine.Nodes.Action.ParallelGroupTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Action.ParallelGroup

  describe "execute/2" do
    test "returns completed with empty tasks" do
      assert {:completed, %{tasks: [], message: _}} =
               ParallelGroup.execute(%{"tasks" => []}, %{})
    end

    test "executes multiple tasks in parallel" do
      config = %{
        "tasks" => [
          %{
            "id" => "cond1",
            "type" => "condition",
            "config" => %{"field" => "plan", "value" => "premium"}
          },
          %{
            "id" => "cond2",
            "type" => "condition",
            "config" => %{"field" => "age", "operator" => "greater_than", "value" => 18}
          }
        ],
        "timeout_ms" => 5000
      }

      context = %{"plan" => "premium", "age" => 25}

      assert {:completed, results} = ParallelGroup.execute(config, context)
      assert Map.has_key?(results, "cond1")
      assert Map.has_key?(results, "cond2")
      assert results["cond1"].status == "completed"
      assert results["cond2"].status == "completed"
    end

    test "handles unknown node type gracefully" do
      config = %{
        "tasks" => [
          %{"id" => "bad", "type" => "nonexistent_node", "config" => %{}}
        ],
        "on_error" => "continue"
      }

      assert {:completed, results} = ParallelGroup.execute(config, %{})
      assert results["bad"].status == "failed"
    end

    test "fails all when on_error=fail_all and a task fails" do
      config = %{
        "tasks" => [
          %{"id" => "good", "type" => "condition", "config" => %{"field" => "x", "value" => 1}},
          %{"id" => "bad", "type" => "nonexistent_node", "config" => %{}}
        ],
        "on_error" => "fail_all"
      }

      assert {:failed, %{parallel_errors: errors}} = ParallelGroup.execute(config, %{"x" => 1})
      refute Enum.empty?(errors)
    end

    test "continues on error when on_error=continue (default)" do
      config = %{
        "tasks" => [
          %{"id" => "good", "type" => "condition", "config" => %{"field" => "x", "value" => 1}},
          %{"id" => "bad", "type" => "nonexistent_node", "config" => %{}}
        ]
      }

      assert {:completed, results} = ParallelGroup.execute(config, %{"x" => 1})
      assert results["good"].status == "completed"
      assert results["bad"].status == "failed"
    end

    test "dry run returns task summaries" do
      config = %{
        "tasks" => [
          %{"id" => "t1", "type" => "send_email", "config" => %{}},
          %{"id" => "t2", "type" => "send_sms", "config" => %{}}
        ]
      }

      assert {:completed, results} = ParallelGroup.execute(config, %{"_dry_run" => true})
      assert results["t1"].dry_run == true
      assert results["t2"].dry_run == true
    end
  end

  describe "validate/1" do
    test "accepts valid config" do
      config = %{
        "tasks" => [
          %{"id" => "t1", "type" => "send_email", "config" => %{}},
          %{"id" => "t2", "type" => "condition", "config" => %{}}
        ]
      }

      assert :ok = ParallelGroup.validate(config)
    end

    test "rejects tasks without id" do
      config = %{"tasks" => [%{"type" => "send_email"}]}
      assert {:error, errors} = ParallelGroup.validate(config)
      assert Enum.any?(errors, &String.contains?(&1, "id"))
    end

    test "rejects duplicate task IDs" do
      config = %{
        "tasks" => [
          %{"id" => "same", "type" => "a", "config" => %{}},
          %{"id" => "same", "type" => "b", "config" => %{}}
        ]
      }

      assert {:error, errors} = ParallelGroup.validate(config)
      assert Enum.any?(errors, &String.contains?(&1, "Duplicate"))
    end
  end

  describe "category/0" do
    test "returns :action" do
      assert ParallelGroup.category() == :action
    end
  end
end
