defmodule KalciferWeb.HealthController do
  use KalciferWeb, :controller

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
      uptime_seconds: :erlang.statistics(:wall_clock) |> elem(0) |> div(1000)
    }

    json(conn, data)
  end
end
