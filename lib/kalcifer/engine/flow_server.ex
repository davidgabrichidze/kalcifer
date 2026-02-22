defmodule Kalcifer.Engine.FlowServer do
  @moduledoc false

  use GenServer, restart: :transient

  alias Kalcifer.Engine.Duration
  alias Kalcifer.Engine.GraphWalker
  alias Kalcifer.Engine.Jobs.ResumeFlowJob
  alias Kalcifer.Engine.NodeExecutor
  alias Kalcifer.Engine.Persistence.InstanceStore
  alias Kalcifer.Engine.Persistence.StepStore

  defstruct [
    :instance_id,
    :flow_id,
    :customer_id,
    :tenant_id,
    :version_number,
    :graph,
    :current_nodes,
    :context,
    :status,
    :waiting_node_id
  ]

  # --- Public API ---

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: via_tuple(args.instance_id))
  end

  def get_state(instance_id) do
    GenServer.call(via_tuple(instance_id), :get_state)
  end

  defp via_tuple(instance_id) do
    {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}
  end

  # --- GenServer callbacks ---

  @impl true
  def init(args) do
    entry_nodes = GraphWalker.entry_nodes(args.graph)
    entry_node_ids = Enum.map(entry_nodes, & &1["id"])

    {:ok, instance} =
      InstanceStore.create_instance(%{
        flow_id: args.flow_id,
        version_number: args.version_number,
        customer_id: args.customer_id,
        tenant_id: args.tenant_id,
        current_nodes: entry_node_ids
      })

    state = %__MODULE__{
      instance_id: instance.id,
      flow_id: args.flow_id,
      customer_id: args.customer_id,
      tenant_id: args.tenant_id,
      version_number: args.version_number,
      graph: args.graph,
      current_nodes: entry_node_ids,
      context: %{},
      status: :running
    }

    {:ok, state, {:continue, :execute_current}}
  end

  @impl true
  def handle_continue(:execute_current, state) do
    state = execute_nodes(state, state.current_nodes)
    maybe_stop(state)
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:resume, node_id, trigger}, state) do
    node = GraphWalker.find_node(state.graph, node_id)
    {:ok, step} = StepStore.record_step_start(state.instance_id, node, state.version_number)

    case NodeExecutor.resume(node, state.context, trigger) do
      {:completed, result} ->
        StepStore.record_step_complete(step, result)
        state = accumulate_context(state, node_id, result)
        state = %{state | status: :running, waiting_node_id: nil}
        next = resolve_next_nodes(state.graph, node, nil)
        state = continue_from_resume(state, next)
        maybe_stop(state)

      {:branched, branch_key, result} ->
        StepStore.record_step_complete(step, result)
        state = accumulate_context(state, node_id, result)
        state = %{state | status: :running, waiting_node_id: nil}
        next = resolve_next_nodes(state.graph, node, branch_key)
        state = continue_from_resume(state, next)
        maybe_stop(state)

      {:failed, reason} ->
        error = normalize_error(reason)
        StepStore.record_step_fail(step, error)
        state = %{state | status: :failed, waiting_node_id: nil}
        InstanceStore.fail_instance(get_instance(state), inspect(reason))
        maybe_stop(state)
    end
  end

  # --- Execution loop ---

  defp execute_nodes(state, []) do
    state
  end

  defp execute_nodes(state, [node_id | rest]) do
    node = GraphWalker.find_node(state.graph, node_id)

    case execute_single_node(state, node) do
      {:continue, state, next_node_ids} ->
        execute_nodes(state, rest ++ next_node_ids)

      {:waiting, state} ->
        execute_nodes(state, rest)

      {:failed, state} ->
        state
    end
  end

  defp execute_single_node(state, node) do
    {:ok, step} = StepStore.record_step_start(state.instance_id, node, state.version_number)

    case NodeExecutor.execute(node, state.context) do
      {:completed, result} ->
        StepStore.record_step_complete(step, result)
        state = accumulate_context(state, node["id"], result)
        next = resolve_next_nodes(state.graph, node, nil)
        handle_next(state, next)

      {:branched, branch_key, result} ->
        StepStore.record_step_complete(step, result)
        state = accumulate_context(state, node["id"], result)
        next = resolve_next_nodes(state.graph, node, branch_key)
        handle_next(state, next)

      {:waiting, wait_config} ->
        StepStore.record_step_complete(step, wait_config)
        state = %{state | status: :waiting, waiting_node_id: node["id"]}
        persist_current_state(state)
        schedule_resume(node, wait_config, state)
        {:waiting, state}

      {:failed, reason} ->
        error = normalize_error(reason)
        StepStore.record_step_fail(step, error)
        state = %{state | status: :failed}
        InstanceStore.fail_instance(get_instance(state), inspect(reason))
        {:failed, state}

      {:error, {:unknown_node_type, _type}} = error ->
        error_map = %{reason: inspect(error)}
        StepStore.record_step_fail(step, error_map)
        state = %{state | status: :failed}
        InstanceStore.fail_instance(get_instance(state), inspect(error))
        {:failed, state}
    end
  end

  defp handle_next(state, []) do
    # No more nodes — check if this is an exit node result
    state = %{state | current_nodes: [], status: :completed}
    InstanceStore.complete_instance(get_instance(state))
    {:continue, state, []}
  end

  defp handle_next(state, next_nodes) do
    next_ids = Enum.map(next_nodes, & &1["id"])
    all_current = Enum.uniq(state.current_nodes ++ next_ids)
    state = %{state | current_nodes: all_current}
    persist_current_state(state)
    {:continue, state, next_ids}
  end

  defp resolve_next_nodes(graph, node, nil) do
    GraphWalker.next_nodes(graph, node["id"])
  end

  defp resolve_next_nodes(graph, node, branch_key) do
    GraphWalker.next_nodes(graph, node["id"], branch_key)
  end

  defp accumulate_context(state, node_id, result) do
    accumulated = Map.get(state.context, "accumulated", %{})
    accumulated = Map.put(accumulated, node_id, result)
    context = Map.put(state.context, "accumulated", accumulated)
    %{state | context: context}
  end

  defp persist_current_state(state) do
    instance = get_instance(state)

    if instance do
      InstanceStore.update_current_nodes(instance, state.current_nodes)
    end
  end

  defp get_instance(state) do
    InstanceStore.get_instance(state.instance_id)
  end

  # --- Resume helpers ---

  defp continue_from_resume(state, []) do
    state = %{state | current_nodes: [], status: :completed}
    InstanceStore.complete_instance(get_instance(state))
    state
  end

  defp continue_from_resume(state, next_nodes) do
    next_ids = Enum.map(next_nodes, & &1["id"])
    state = %{state | current_nodes: next_ids}
    execute_nodes(state, next_ids)
  end

  # --- Timer scheduling ---

  defp schedule_resume(node, wait_config, state) do
    case node["type"] do
      "wait" ->
        schedule_timer(state, node["id"], wait_config.duration, "timer_expired")

      "wait_until" ->
        schedule_at(state, node["id"], wait_config.until, "timer_expired")

      "wait_for_event" ->
        timeout = node["config"]["timeout"]
        if timeout, do: schedule_timer(state, node["id"], timeout, "timeout")

      _ ->
        :ok
    end
  end

  defp schedule_timer(state, node_id, duration, trigger) do
    case Duration.to_seconds(duration) do
      {:ok, seconds} ->
        scheduled_at = DateTime.add(DateTime.utc_now(), seconds, :second)
        insert_resume_job(state, node_id, trigger, scheduled_at)

      _ ->
        :ok
    end
  end

  defp schedule_at(state, node_id, datetime_string, trigger) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, dt, _} -> insert_resume_job(state, node_id, trigger, dt)
      _ -> :ok
    end
  end

  defp insert_resume_job(state, node_id, trigger, scheduled_at) do
    %{instance_id: state.instance_id, node_id: node_id, trigger: trigger}
    |> ResumeFlowJob.new(scheduled_at: scheduled_at)
    |> Oban.insert()
  end

  defp normalize_error(%{} = error), do: error
  defp normalize_error(reason), do: %{reason: inspect(reason)}

  defp maybe_stop(%{status: :completed} = state), do: {:stop, :normal, state}
  defp maybe_stop(%{status: :failed} = state), do: {:stop, :normal, state}
  defp maybe_stop(state), do: {:noreply, state}
end
