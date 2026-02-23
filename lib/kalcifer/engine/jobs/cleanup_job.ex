defmodule Kalcifer.Engine.Jobs.CleanupJob do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  import Ecto.Query

  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Repo

  @stale_days 7
  @archive_days 30

  @impl true
  def perform(_job) do
    stale_count = mark_stale_instances()
    archive_count = archive_old_instances()

    {:ok, %{stale_marked: stale_count, archived: archive_count}}
  end

  defp mark_stale_instances do
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_days, :day)

    {count, _} =
      from(i in FlowInstance,
        where: i.status == "running",
        where: i.updated_at < ^cutoff
      )
      |> Repo.update_all(
        set: [
          status: "failed",
          exit_reason: "stale_timeout"
        ]
      )

    count
  end

  defp archive_old_instances do
    cutoff = DateTime.add(DateTime.utc_now(), -@archive_days, :day)

    {count, _} =
      from(i in FlowInstance,
        where: i.status in ["completed", "exited", "failed"],
        where: i.updated_at < ^cutoff
      )
      |> Repo.delete_all()

    count
  end
end
