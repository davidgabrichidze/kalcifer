defmodule Kalcifer.Engine.CircuitBreaker do
  @moduledoc false

  use GenServer

  @failure_threshold 5
  @cooldown_ms :timer.seconds(30)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def allow?(server \\ __MODULE__, channel) do
    GenServer.call(server, {:allow?, channel})
  end

  def record_success(server \\ __MODULE__, channel) do
    GenServer.cast(server, {:success, channel})
  end

  def record_failure(server \\ __MODULE__, channel) do
    GenServer.cast(server, {:failure, channel})
  end

  def status(server \\ __MODULE__, channel) do
    GenServer.call(server, {:status, channel})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{circuits: %{}}}
  end

  @impl true
  def handle_call({:allow?, channel}, _from, state) do
    circuit = Map.get(state.circuits, channel, default_circuit())

    result =
      case circuit.state do
        :closed -> true
        :open -> check_cooldown(circuit)
        :half_open -> true
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:status, channel}, _from, state) do
    circuit = Map.get(state.circuits, channel, default_circuit())
    {:reply, circuit.state, state}
  end

  @impl true
  def handle_cast({:success, channel}, state) do
    circuit = Map.get(state.circuits, channel, default_circuit())

    circuit = %{circuit | failure_count: 0, state: :closed}
    circuits = Map.put(state.circuits, channel, circuit)

    {:noreply, %{state | circuits: circuits}}
  end

  @impl true
  def handle_cast({:failure, channel}, state) do
    circuit = Map.get(state.circuits, channel, default_circuit())

    count = circuit.failure_count + 1

    circuit =
      if count >= @failure_threshold do
        %{
          circuit
          | failure_count: count,
            state: :open,
            opened_at: System.monotonic_time(:millisecond)
        }
      else
        %{circuit | failure_count: count}
      end

    circuits = Map.put(state.circuits, channel, circuit)
    {:noreply, %{state | circuits: circuits}}
  end

  defp check_cooldown(circuit) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - circuit.opened_at

    if elapsed >= @cooldown_ms do
      true
    else
      false
    end
  end

  defp default_circuit do
    %{state: :closed, failure_count: 0, opened_at: nil}
  end
end
