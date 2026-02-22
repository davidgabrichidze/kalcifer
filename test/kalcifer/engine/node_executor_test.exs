defmodule Kalcifer.Engine.NodeExecutorTest.CrashingNode do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(_config, _context), do: raise("boom")

  @impl true
  def config_schema, do: %{}

  @impl true
  def category, do: :task
end

defmodule Kalcifer.Engine.NodeExecutorTest do
  use ExUnit.Case, async: false

  alias Kalcifer.Engine.NodeExecutor
  alias Kalcifer.Engine.NodeExecutorTest.CrashingNode
  alias Kalcifer.Engine.NodeRegistry

  describe "execute/3" do
    test "dispatches to correct node module and returns completed" do
      node = %{"type" => "event_entry", "config" => %{"event_type" => "signed_up"}}
      assert {:completed, %{event_type: "signed_up"}} = NodeExecutor.execute(node, %{})
    end

    test "dispatches branching node and returns branched" do
      node = %{
        "type" => "condition",
        "config" => %{"field" => "status", "value" => "active"}
      }

      context = %{"status" => "active"}
      assert {:branched, "true", _result} = NodeExecutor.execute(node, context)
    end

    test "dispatches waiting node and returns waiting" do
      node = %{"type" => "wait", "config" => %{"duration" => "3d"}}
      assert {:waiting, %{duration: "3d"}} = NodeExecutor.execute(node, %{})
    end

    test "returns error for unknown node type" do
      node = %{"type" => "nonexistent", "config" => %{}}
      assert {:error, {:unknown_node_type, "nonexistent"}} = NodeExecutor.execute(node, %{})
    end

    test "catches crashes in node execution" do
      NodeRegistry.register("crashing_test", CrashingNode)
      node = %{"type" => "crashing_test", "config" => %{}}
      assert {:failed, %{reason: "boom"}} = NodeExecutor.execute(node, %{})
    end

    test "handles nil config gracefully" do
      node = %{"type" => "journey_exit"}
      assert {:completed, %{exit: true}} = NodeExecutor.execute(node, %{})
    end
  end

  describe "resume/4" do
    test "resumes a wait_for_event node with event trigger" do
      node = %{
        "type" => "wait_for_event",
        "config" => %{"event_type" => "email_opened", "timeout" => "3d"}
      }

      trigger = %{event_type: "email_opened"}
      assert {:branched, "event_received", _} = NodeExecutor.resume(node, %{}, trigger)
    end

    test "resumes a wait_for_event node with timeout trigger" do
      node = %{
        "type" => "wait_for_event",
        "config" => %{"event_type" => "email_opened", "timeout" => "3d"}
      }

      assert {:branched, "timed_out", _} = NodeExecutor.resume(node, %{}, :timeout)
    end

    test "returns failed for non-resumable node" do
      node = %{"type" => "send_email", "config" => %{}}
      assert {:failed, :not_resumable} = NodeExecutor.resume(node, %{}, :some_trigger)
    end
  end
end
