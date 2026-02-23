defmodule KalciferWeb.HealthController do
  use KalciferWeb, :controller

  import Ecto.Query

  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Repo

  def show(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  def metrics(conn, _params) do
    memory = :erlang.memory()

    data = %{
      vm: %{
        memory_mb: div(memory[:total], 1_048_576),
        process_count: :erlang.system_info(:process_count),
        run_queue: :erlang.statistics(:total_run_queue_lengths_all)
      },
      uptime_seconds: :erlang.statistics(:wall_clock) |> elem(0) |> div(1000),
      instances: instance_counts(),
      oban: oban_queue_stats()
    }

    json(conn, data)
  end

  defp instance_counts do
    from(i in FlowInstance,
      where: i.status in ["running", "waiting"],
      group_by: i.status,
      select: {i.status, count(i.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp oban_queue_stats do
    from(j in Oban.Job,
      where: j.state in ["available", "executing", "scheduled"],
      group_by: [j.queue, j.state],
      select: {j.queue, j.state, count(j.id)}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_q, state, count} -> {state, count} end)
    |> Map.new(fn {queue, states} -> {queue, Map.new(states)} end)
  end
end
