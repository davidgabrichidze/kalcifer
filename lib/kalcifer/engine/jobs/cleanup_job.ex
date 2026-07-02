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

    {running, _} =
      from(i in FlowInstance,
        where: i.status == "running",
        where: i.updated_at < ^cutoff
      )
      |> Repo.update_all(set: [status: "failed", exit_reason: "stale_timeout"])

    running + reap_orphaned_waiters(cutoff)
  end

  # A "waiting" instance is only stuck if it has no pending resume job — a
  # long legitimate wait (e.g. "30d") keeps a scheduled job and is left alone.
  # This catches instances stranded by a wait node whose config left no timer.
  defp reap_orphaned_waiters(cutoff) do
    pending_states = ~w(scheduled available retryable executing)

    active_instance_ids =
      from(j in "oban_jobs",
        where: j.queue == "delayed_resume" and j.state in ^pending_states,
        select: fragment("?->>'instance_id'", j.args)
      )
      |> Repo.all()

    {count, _} =
      from(i in FlowInstance,
        where: i.status == "waiting",
        where: i.updated_at < ^cutoff,
        where: i.id not in ^active_instance_ids
      )
      |> Repo.update_all(set: [status: "failed", exit_reason: "stale_no_resume_job"])

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
