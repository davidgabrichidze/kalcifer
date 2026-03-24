defmodule Kalcifer.Engine.Nodes.Action.ParallelGroup do
  @moduledoc """
  Executes multiple tasks in parallel using Task.async_stream.

  Config:
    - tasks: list of task definitions, each with:
      - id: unique identifier for this task's result
      - type: node type to execute (e.g. "send_email", "call_webhook")
      - config: config map passed to the node's execute/2
    - timeout_ms: max time to wait for all tasks (default: 30_000)
    - on_error: "continue" (default) or "fail_all"

  Results are accumulated under each task's id:
    context.accumulated.parallel_group_1 = %{
      "task_a" => %{status: "completed", result: ...},
      "task_b" => %{status: "completed", result: ...}
    }

  Example config:
    %{
      "tasks" => [
        %{"id" => "email", "type" => "send_email", "config" => %{"subject" => "Hello"}},
        %{"id" => "sms", "type" => "send_sms", "config" => %{"body" => "Hi!"}}
      ],
      "timeout_ms" => 10000,
      "on_error" => "continue"
    }
  """

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Engine.NodeRegistry

  @default_timeout 30_000

  @impl true
  def execute(config, context) do
    tasks = config["tasks"] || []
    timeout = config["timeout_ms"] || @default_timeout
    on_error = config["on_error"] || "continue"

    if tasks == [] do
      {:completed, %{tasks: [], message: "No tasks to execute"}}
    else
      if context["_dry_run"] do
        execute_dry_run(tasks)
      else
        execute_parallel(tasks, context, timeout, on_error)
      end
    end
  end

  @impl true
  def config_schema do
    %{
      "tasks" => %{
        "type" => "array",
        "required" => true,
        "description" => "List of tasks to execute in parallel"
      },
      "timeout_ms" => %{
        "type" => "integer",
        "default" => @default_timeout,
        "description" => "Max milliseconds to wait for all tasks"
      },
      "on_error" => %{
        "type" => "string",
        "enum" => ["continue", "fail_all"],
        "default" => "continue",
        "description" => "Error handling: continue other tasks or fail all"
      }
    }
  end

  @impl true
  def validate(config) do
    tasks = config["tasks"] || []

    errors =
      tasks
      |> Enum.with_index()
      |> Enum.flat_map(fn {task, idx} ->
        cond do
          not is_map(task) -> ["Task #{idx}: must be a map"]
          not is_binary(task["id"]) -> ["Task #{idx}: missing 'id'"]
          not is_binary(task["type"]) -> ["Task #{idx}: missing 'type'"]
          true -> []
        end
      end)

    ids = Enum.map(tasks, & &1["id"]) |> Enum.filter(&is_binary/1)
    dup_errors = if length(ids) != length(Enum.uniq(ids)), do: ["Duplicate task IDs"], else: []

    case errors ++ dup_errors do
      [] -> :ok
      errs -> {:error, errs}
    end
  end

  @impl true
  def category, do: :action

  # ── Private ──────────────────────────────────────────

  defp execute_dry_run(tasks) do
    results =
      tasks
      |> Enum.map(fn task ->
        {task["id"],
         %{
           status: "completed",
           dry_run: true,
           type: task["type"],
           would_execute: true
         }}
      end)
      |> Map.new()

    {:completed, results}
  end

  defp execute_parallel(tasks, context, timeout, on_error) do
    results =
      tasks
      |> Task.async_stream(
        fn task -> execute_task(task, context) end,
        timeout: timeout,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.zip(tasks)
      |> Enum.map(fn {result, task} ->
        task_result =
          case result do
            {:ok, {:completed, data}} ->
              %{status: "completed", result: data}

            {:ok, {:branched, branch, data}} ->
              %{status: "completed", branch: branch, result: data}

            {:ok, {:failed, reason}} ->
              %{status: "failed", error: inspect(reason)}

            {:ok, {:waiting, _}} ->
              %{status: "skipped", reason: "waiting nodes not supported in parallel"}

            {:exit, :timeout} ->
              %{status: "failed", error: "timeout"}

            {:exit, reason} ->
              %{status: "failed", error: "exit: #{inspect(reason)}"}
          end

        {task["id"], task_result}
      end)
      |> Map.new()

    # Check if any failed
    failed = Enum.filter(results, fn {_, r} -> r.status == "failed" end)

    if on_error == "fail_all" and length(failed) > 0 do
      {:failed, %{parallel_errors: Enum.map(failed, fn {id, r} -> "#{id}: #{r.error}" end)}}
    else
      {:completed, results}
    end
  end

  defp execute_task(task, context) do
    node_type = task["type"]
    node_config = task["config"] || %{}

    case NodeRegistry.lookup(node_type) do
      {:ok, module} ->
        try do
          module.execute(node_config, context)
        rescue
          error ->
            {:failed, %{reason: Exception.message(error)}}
        end

      :error ->
        {:failed, {:unknown_node_type, node_type}}
    end
  end
end
