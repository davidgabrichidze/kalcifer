defmodule Kalcifer.Engine.Nodes.Action.SubFlow do
  @moduledoc """
  Executes another flow as a child instance (sub-flow).

  Config:
    - flow_id: UUID of the flow to execute as sub-flow
    - context_mapping: map of parent_key → child_key for context passing (optional)
    - wait: boolean — if true, waits for child flow to complete (default: false)
    - timeout_ms: max wait time in ms (default: 60_000, only when wait=true)

  On dry run: returns sub-flow metadata without actually executing.

  Results:
    - wait=false: returns {instance_id} immediately
    - wait=true: returns child flow's accumulated results (or timeout error)
  """

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Engine.FlowTrigger
  alias Kalcifer.Flows

  @default_timeout 60_000

  @impl true
  def execute(config, context) do
    flow_id = config["flow_id"]
    context_mapping = config["context_mapping"] || %{}
    wait = config["wait"] || false
    timeout = config["timeout_ms"] || @default_timeout

    if context["_dry_run"] do
      execute_dry_run(flow_id, context_mapping)
    else
      execute_sub_flow(flow_id, context_mapping, context, wait, timeout)
    end
  end

  @impl true
  def validate(config) do
    errors = []

    errors =
      if is_binary(config["flow_id"]) and config["flow_id"] != "" do
        errors
      else
        ["flow_id is required" | errors]
      end

    case errors do
      [] -> :ok
      errs -> {:error, Enum.reverse(errs)}
    end
  end

  @impl true
  def config_schema do
    %{
      "flow_id" => %{
        "type" => "string",
        "required" => true,
        "description" => "UUID of the flow to execute as sub-flow"
      },
      "context_mapping" => %{
        "type" => "object",
        "description" => "Map parent context keys to child context keys"
      },
      "wait" => %{
        "type" => "boolean",
        "default" => false,
        "description" => "Wait for sub-flow completion before continuing"
      },
      "timeout_ms" => %{
        "type" => "integer",
        "default" => @default_timeout,
        "description" => "Max wait time when wait=true"
      }
    }
  end

  @impl true
  def category, do: :action

  # ── Private ──────────────────────────────────────────

  defp execute_dry_run(flow_id, context_mapping) do
    flow_name =
      try do
        case Flows.get_flow(flow_id) do
          %{name: name} -> name
          _ -> "(#{flow_id})"
        end
      rescue
        _ -> "(#{flow_id})"
      end

    {:completed,
     %{
       dry_run: true,
       sub_flow: %{
         flow_id: flow_id,
         flow_name: flow_name,
         context_mapping: context_mapping,
         would_execute: true
       }
     }}
  end

  defp execute_sub_flow(flow_id, context_mapping, parent_context, wait, timeout) do
    # Build child context from parent using mapping
    child_context = build_child_context(parent_context, context_mapping)

    customer_id = parent_context["_customer_id"] || "sub_flow"
    _tenant_id = parent_context["_tenant_id"]

    case Flows.get_flow(flow_id) do
      nil ->
        {:failed, %{reason: "Sub-flow not found: #{flow_id}"}}

      flow ->
        case FlowTrigger.trigger(flow.id, customer_id, child_context) do
          {:ok, instance_id, _pid} ->
            if wait do
              wait_for_completion(instance_id, timeout)
            else
              {:completed,
               %{
                 sub_flow: true,
                 instance_id: instance_id,
                 flow_id: flow_id,
                 async: true
               }}
            end

          {:error, reason} ->
            {:failed, %{reason: "Failed to start sub-flow: #{inspect(reason)}"}}
        end
    end
  end

  defp build_child_context(parent_context, mapping) when map_size(mapping) == 0 do
    # Pass through system context keys
    parent_context
    |> Map.take(["_customer_id", "_tenant_id", "_email", "_phone"])
  end

  defp build_child_context(parent_context, mapping) do
    base = Map.take(parent_context, ["_customer_id", "_tenant_id", "_email", "_phone"])

    Enum.reduce(mapping, base, fn {parent_key, child_key}, acc ->
      case Map.get(parent_context, parent_key) do
        nil -> acc
        value -> Map.put(acc, child_key, value)
      end
    end)
  end

  defp wait_for_completion(instance_id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    poll_result(instance_id, deadline)
  end

  defp poll_result(instance_id, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:completed,
       %{
         sub_flow: true,
         instance_id: instance_id,
         status: "timeout",
         message: "Sub-flow did not complete within timeout"
       }}
    else
      case Kalcifer.Engine.Persistence.InstanceStore.get_instance(instance_id) do
        %{status: "completed", context: ctx} ->
          {:completed,
           %{
             sub_flow: true,
             instance_id: instance_id,
             status: "completed",
             result: Map.get(ctx || %{}, "accumulated", %{})
           }}

        %{status: "failed"} ->
          {:completed,
           %{
             sub_flow: true,
             instance_id: instance_id,
             status: "failed"
           }}

        _ ->
          Process.sleep(100)
          poll_result(instance_id, deadline)
      end
    end
  end
end
