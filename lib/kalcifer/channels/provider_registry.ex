defmodule Kalcifer.Channels.ProviderRegistry do
  @moduledoc false

  use GenServer

  @table :kalcifer_provider_registry

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def lookup(channel) when is_atom(channel) do
    case :ets.lookup(@table, channel) do
      [{^channel, module}] -> {:ok, module}
      [] -> :error
    end
  end

  def register(channel, module) when is_atom(channel) do
    GenServer.call(__MODULE__, {:register, channel, module})
  end

  def list_all do
    :ets.tab2list(@table)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])

    providers = Application.get_env(:kalcifer, :channel_providers, %{})

    for {channel, module} <- providers do
      :ets.insert(table, {channel, module})
    end

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, channel, module}, _from, state) do
    :ets.insert(state.table, {channel, module})
    {:reply, :ok, state}
  end
end
