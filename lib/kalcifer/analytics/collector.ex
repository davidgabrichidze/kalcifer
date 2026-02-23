defmodule Kalcifer.Analytics.Collector do
  @moduledoc false

  use GenServer

  alias Kalcifer.Analytics

  @flush_interval :timer.seconds(10)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def record_step(server \\ __MODULE__, event) do
    GenServer.cast(server, {:record_step, event})
  end

  def record_instance(server \\ __MODULE__, event) do
    GenServer.cast(server, {:record_instance, event})
  end

  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    schedule_flush()
    {:ok, %{flow_stats: %{}, node_stats: %{}}}
  end

  @impl true
  def handle_cast({:record_step, event}, state) do
    state = increment_node_stats(state, event)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:record_instance, event}, state) do
    state = increment_flow_stats(state, event)
    {:noreply, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    persist_stats(state)
    {:reply, :ok, %{flow_stats: %{}, node_stats: %{}}}
  end

  @impl true
  def handle_info(:flush, state) do
    persist_stats(state)
    schedule_flush()
    {:noreply, %{flow_stats: %{}, node_stats: %{}}}
  end

  # Aggregation helpers

  defp increment_flow_stats(state, %{flow_id: flow_id, version_number: vn, type: type}) do
    date = Date.utc_today()
    key = {flow_id, vn, date}

    flow_stats =
      Map.update(state.flow_stats, key, %{type => 1}, fn counts ->
        Map.update(counts, type, 1, &(&1 + 1))
      end)

    %{state | flow_stats: flow_stats}
  end

  defp increment_node_stats(state, %{
         flow_id: flow_id,
         version_number: vn,
         node_id: node_id,
         status: status,
         branch_key: branch_key
       }) do
    date = Date.utc_today()
    key = {flow_id, vn, node_id, date}

    node_stats =
      Map.update(
        state.node_stats,
        key,
        initial_node_count(status, branch_key),
        fn counts ->
          counts = Map.update(counts, :executed, 1, &(&1 + 1))

          counts =
            case status do
              :completed -> Map.update(counts, :completed, 1, &(&1 + 1))
              :failed -> Map.update(counts, :failed, 1, &(&1 + 1))
              _ -> counts
            end

          if branch_key do
            branches = Map.get(counts, :branch_counts, %{})
            branches = Map.update(branches, branch_key, 1, &(&1 + 1))
            Map.put(counts, :branch_counts, branches)
          else
            counts
          end
        end
      )

    %{state | node_stats: node_stats}
  end

  defp initial_node_count(status, branch_key) do
    base = %{executed: 1, completed: 0, failed: 0, branch_counts: %{}}

    base =
      case status do
        :completed -> %{base | completed: 1}
        :failed -> %{base | failed: 1}
        _ -> base
      end

    if branch_key do
      %{base | branch_counts: %{branch_key => 1}}
    else
      base
    end
  end

  defp persist_stats(%{flow_stats: flow_stats, node_stats: node_stats}) do
    Enum.each(flow_stats, fn {{flow_id, vn, date}, counts} ->
      Analytics.upsert_flow_stats(flow_id, vn, date, counts)
    end)

    Enum.each(node_stats, fn {{flow_id, vn, node_id, date}, counts} ->
      Analytics.upsert_node_stats(flow_id, vn, node_id, date, counts)
    end)
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end
end
