defmodule Kalcifer.Engine.JourneyServer do
  @moduledoc false

  use GenServer, restart: :transient

  alias Kalcifer.Engine.GraphWalker
  alias Kalcifer.Engine.NodeExecutor
  alias Kalcifer.Engine.Persistence.InstanceStore
  alias Kalcifer.Engine.Persistence.StepStore

  defstruct [
    :instance_id,
    :journey_id,
    :customer_id,
    :tenant_id,
    :version_number,
    :graph,
    :current_nodes,
    :context,
    :status
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
        journey_id: args.journey_id,
        version_number: args.version_number,
        customer_id: args.customer_id,
        tenant_id: args.tenant_id,
        current_nodes: entry_node_ids
      })

    state = %__MODULE__{
      instance_id: instance.id,
      journey_id: args.journey_id,
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
        state = %{state | status: :waiting}
        persist_current_state(state)
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

  defp normalize_error(%{} = error), do: error
  defp normalize_error(reason), do: %{reason: inspect(reason)}

  defp maybe_stop(%{status: :completed} = state), do: {:stop, :normal, state}
  defp maybe_stop(%{status: :failed} = state), do: {:stop, :normal, state}
  defp maybe_stop(state), do: {:noreply, state}
end
