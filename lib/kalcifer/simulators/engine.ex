defmodule Kalcifer.Simulators.Engine do
  @moduledoc """
  Executes scheduled simulator work. Providers hand it closures with a
  delay; the engine runs them after the timer fires. Kept as a single
  named process so tests can grant it sandbox access and synchronize on
  its mailbox via `sync/0`.
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def schedule(server \\ __MODULE__, delay_ms, fun) when is_function(fun, 0) do
    Process.send_after(server, {:run, fun}, delay_ms)
  end

  @doc "Blocks until all messages already in the mailbox are processed."
  def sync(server \\ __MODULE__) do
    GenServer.call(server, :sync)
  end

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info({:run, fun}, state) do
    fun.()
    {:noreply, state}
  rescue
    error ->
      Logger.warning("simulator step failed: #{Exception.message(error)}")
      {:noreply, state}
  end
end
