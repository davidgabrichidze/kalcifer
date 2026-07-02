defmodule Kalcifer.Engine.CircuitBreaker do
  @moduledoc false

  use GenServer

  @default_failure_threshold 5
  @default_cooldown_ms :timer.seconds(30)

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

  def reset(server \\ __MODULE__, channel) do
    GenServer.cast(server, {:reset, channel})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    failure_threshold = Keyword.get(opts, :failure_threshold, @default_failure_threshold)
    cooldown_ms = Keyword.get(opts, :cooldown_ms, @default_cooldown_ms)
    {:ok, %{circuits: %{}, failure_threshold: failure_threshold, cooldown_ms: cooldown_ms}}
  end

  @impl true
  def handle_call({:allow?, channel}, _from, state) do
    circuit = Map.get(state.circuits, channel, default_circuit())

    now = System.monotonic_time(:millisecond)

    {result, circuit} =
      case circuit.state do
        :closed ->
          {true, circuit}

        :open ->
          if now - circuit.opened_at >= state.cooldown_ms do
            # First caller past cooldown becomes the probe.
            {true, %{circuit | state: :half_open, probe_at: now}}
          else
            {false, circuit}
          end

        :half_open ->
          # Admit only one probe per cooldown window: concurrent callers are
          # rejected until the probe resolves (success → closed, failure →
          # open) so a still-down provider isn't hit by a thundering herd.
          # If the probe never reports back, a fresh one is allowed after the
          # next window rather than wedging the circuit shut forever.
          if now - circuit.probe_at >= state.cooldown_ms do
            {true, %{circuit | probe_at: now}}
          else
            {false, circuit}
          end
      end

    circuits = Map.put(state.circuits, channel, circuit)
    {:reply, result, %{state | circuits: circuits}}
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

    circuit =
      if circuit.state == :half_open do
        %{circuit | state: :open, opened_at: System.monotonic_time(:millisecond)}
      else
        count = circuit.failure_count + 1

        if count >= state.failure_threshold do
          %{
            circuit
            | failure_count: count,
              state: :open,
              opened_at: System.monotonic_time(:millisecond)
          }
        else
          %{circuit | failure_count: count}
        end
      end

    circuits = Map.put(state.circuits, channel, circuit)
    {:noreply, %{state | circuits: circuits}}
  end

  @impl true
  def handle_cast({:reset, channel}, state) do
    circuits = Map.put(state.circuits, channel, default_circuit())
    {:noreply, %{state | circuits: circuits}}
  end

  defp default_circuit do
    %{state: :closed, failure_count: 0, opened_at: nil, probe_at: nil}
  end
end
