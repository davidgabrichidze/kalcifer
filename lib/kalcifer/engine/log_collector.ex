defmodule Kalcifer.Engine.LogCollector do
  @moduledoc """
  Ring buffer that captures recent log messages for the Engine Room dashboard.
  Stores the last N log entries in an Agent for quick retrieval.
  """

  use GenServer

  @max_entries 100
  @name __MODULE__

  # ── Public API ──────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc "Push a log entry (called from Logger handler)"
  def push(level, message, metadata \\ %{}) do
    entry = %{
      level: to_string(level),
      message: truncate(message, 500),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      source: Map.get(metadata, :source, nil),
      module: Map.get(metadata, :module, nil) |> inspect_module()
    }

    GenServer.cast(@name, {:push, entry})
  rescue
    _ -> :ok
  end

  @doc "Get the last N log entries (newest first)"
  def recent(limit \\ 50) do
    GenServer.call(@name, {:recent, limit})
  rescue
    _ -> []
  end

  # ── GenServer callbacks ─────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %{entries: :queue.new(), count: 0}}
  end

  @impl true
  def handle_cast({:push, entry}, %{entries: q, count: c} = state) do
    q = :queue.in(entry, q)

    {q, c} =
      if c >= @max_entries do
        {{:value, _}, q} = :queue.out(q)
        {q, c}
      else
        {q, c + 1}
      end

    {:noreply, %{state | entries: q, count: c}}
  end

  @impl true
  def handle_call({:recent, limit}, _from, %{entries: q} = state) do
    entries =
      q
      |> :queue.to_list()
      |> Enum.reverse()
      |> Enum.take(limit)

    {:reply, entries, state}
  end

  # ── Helpers ─────────────────────────────────────────────

  defp truncate(msg, max) when is_binary(msg) do
    if String.length(msg) > max, do: String.slice(msg, 0, max) <> "…", else: msg
  end

  defp truncate(msg, max), do: truncate(to_string(msg), max)

  defp inspect_module(nil), do: nil
  defp inspect_module(mod) when is_atom(mod), do: inspect(mod)
  defp inspect_module(other), do: to_string(other)
end
