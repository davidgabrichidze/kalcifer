defmodule KalciferWeb.EngineController do
  @moduledoc """
  Engine Room API — consolidated endpoint for admin dashboard data.
  Returns node registry, oban queue stats, BEAM VM health, and DB info.
  """
  use KalciferWeb, :controller

  import Ecto.Query

  alias Kalcifer.Engine.{LogCollector, NodeRegistry}
  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Repo

  @doc """
  GET /api/v1/engine

  Returns a consolidated snapshot of engine state:
    - node_registry: all registered nodes with category info
    - oban: queue stats (concurrency, active, completed, failed)
    - vm: BEAM VM metrics (memory, processes, schedulers, uptime)
    - db: PostgreSQL connection pool info
    - instances: active flow instance counts by status
  """
  def show(conn, _params) do
    json(conn, %{
      node_registry: node_registry_data(),
      oban: oban_data(),
      vm: vm_data(),
      db: db_data(),
      instances: instance_data(),
      logs: LogCollector.recent(50)
    })
  end

  # ── Node Registry ──────────────────────────────────────

  defp node_registry_data do
    nodes =
      NodeRegistry.list_all()
      |> Enum.map(fn {type, module} ->
        category = safe_category(module)

        %{
          type: type,
          module: inspect(module),
          category: category
        }
      end)
      |> Enum.sort_by(fn n -> {category_order(n.category), n.type} end)

    categories =
      nodes
      |> Enum.group_by(& &1.category)
      |> Enum.map(fn {cat, items} -> {cat, length(items)} end)
      |> Map.new()

    %{
      total: length(nodes),
      nodes: nodes,
      categories: categories
    }
  end

  defp safe_category(module) do
    Code.ensure_loaded(module)

    if function_exported?(module, :category, 0) do
      module.category() |> to_string()
    else
      "unknown"
    end
  rescue
    _ -> "unknown"
  end

  defp category_order("trigger"), do: 0
  defp category_order("condition"), do: 1
  defp category_order("wait"), do: 2
  defp category_order("action"), do: 3
  defp category_order("end"), do: 4
  defp category_order(_), do: 5

  # ── Oban Queues ────────────────────────────────────────

  defp oban_data do
    # Queue configuration from app config
    queues = Application.get_env(:kalcifer, Oban, [])[:queues] || []

    queue_stats =
      from(j in Oban.Job,
        group_by: [j.queue, j.state],
        select: {j.queue, j.state, count(j.id)}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), fn {_q, state, count} -> {state, count} end)
      |> Map.new(fn {queue, states} -> {queue, Map.new(states)} end)

    # Completed jobs in last 24h
    one_day_ago = DateTime.utc_now() |> DateTime.add(-86_400)

    completed_24h =
      from(j in Oban.Job,
        where: j.state == "completed" and j.completed_at >= ^one_day_ago,
        group_by: j.queue,
        select: {j.queue, count(j.id)}
      )
      |> Repo.all()
      |> Map.new()

    # Failed jobs in last 24h
    failed_24h =
      from(j in Oban.Job,
        where: j.state in ["retryable", "discarded"] and j.attempted_at >= ^one_day_ago,
        group_by: j.queue,
        select: {j.queue, count(j.id)}
      )
      |> Repo.all()
      |> Map.new()

    queue_list =
      Enum.map(queues, fn {name, concurrency} ->
        name_str = to_string(name)
        stats = Map.get(queue_stats, name_str, %{})

        %{
          name: name_str,
          concurrency: concurrency,
          executing: Map.get(stats, "executing", 0),
          available: Map.get(stats, "available", 0),
          scheduled: Map.get(stats, "scheduled", 0),
          completed_24h: Map.get(completed_24h, name_str, 0),
          failed_24h: Map.get(failed_24h, name_str, 0)
        }
      end)

    total_concurrency = Enum.reduce(queue_list, 0, fn q, acc -> acc + q.concurrency end)
    total_completed = Enum.reduce(queue_list, 0, fn q, acc -> acc + q.completed_24h end)
    total_failed = Enum.reduce(queue_list, 0, fn q, acc -> acc + q.failed_24h end)

    %{
      queues: queue_list,
      total_concurrency: total_concurrency,
      total_completed_24h: total_completed,
      total_failed_24h: total_failed
    }
  end

  # ── BEAM VM ────────────────────────────────────────────

  defp vm_data do
    memory = :erlang.memory()
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    %{
      memory_total_mb: div(memory[:total], 1_048_576),
      memory_processes_mb: div(memory[:processes], 1_048_576),
      memory_ets_mb: div(memory[:ets], 1_048_576),
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      schedulers: :erlang.system_info(:schedulers_online),
      run_queue: :erlang.statistics(:total_run_queue_lengths_all),
      uptime_seconds: div(uptime_ms, 1000),
      otp_release: to_string(:erlang.system_info(:otp_release)),
      elixir_version: System.version()
    }
  end

  # ── DB ─────────────────────────────────────────────────

  defp db_data do
    # Check pool status if available
    pool_size =
      Application.get_env(:kalcifer, Kalcifer.Repo, [])[:pool_size] || 10

    # Quick latency check
    {latency_us, _} = :timer.tc(fn -> Repo.query!("SELECT 1") end)

    %{
      pool_size: pool_size,
      latency_ms: Float.round(latency_us / 1000, 1),
      adapter: "PostgreSQL"
    }
  end

  # ── Flow Instances ─────────────────────────────────────

  defp instance_data do
    counts =
      from(i in FlowInstance,
        where: i.status in ["running", "waiting"],
        group_by: i.status,
        select: {i.status, count(i.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      running: Map.get(counts, "running", 0),
      waiting: Map.get(counts, "waiting", 0),
      total_active: Map.get(counts, "running", 0) + Map.get(counts, "waiting", 0)
    }
  end
end
