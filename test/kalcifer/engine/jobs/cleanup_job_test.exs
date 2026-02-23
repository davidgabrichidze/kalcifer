defmodule Kalcifer.Engine.Jobs.CleanupJobTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Engine.Jobs.CleanupJob
  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Repo

  test "marks stale running instances as failed" do
    # Create a stale instance (updated 8 days ago)
    eight_days_ago = DateTime.add(DateTime.utc_now(), -8, :day) |> DateTime.truncate(:second)
    instance = insert(:flow_instance, status: "running")

    Repo.update_all(
      from(i in FlowInstance, where: i.id == ^instance.id),
      set: [updated_at: eight_days_ago]
    )

    import Ecto.Query
    job = %Oban.Job{args: %{}}
    assert {:ok, %{stale_marked: 1}} = CleanupJob.perform(job)

    reloaded = Repo.get(FlowInstance, instance.id)
    assert reloaded.status == "failed"
  end

  test "does not mark recent running instances" do
    insert(:flow_instance, status: "running")

    job = %Oban.Job{args: %{}}
    assert {:ok, %{stale_marked: 0}} = CleanupJob.perform(job)
  end

  test "deletes old completed instances" do
    thirty_one_days_ago =
      DateTime.add(DateTime.utc_now(), -31, :day) |> DateTime.truncate(:second)

    instance =
      insert(:flow_instance,
        status: "completed",
        completed_at: thirty_one_days_ago
      )

    import Ecto.Query

    Repo.update_all(
      from(i in FlowInstance, where: i.id == ^instance.id),
      set: [updated_at: thirty_one_days_ago]
    )

    job = %Oban.Job{args: %{}}
    assert {:ok, %{archived: 1}} = CleanupJob.perform(job)

    assert Repo.get(FlowInstance, instance.id) == nil
  end
end
