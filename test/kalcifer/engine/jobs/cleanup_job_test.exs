defmodule Kalcifer.Engine.Jobs.CleanupJobTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Engine.Jobs.CleanupJob
  alias Kalcifer.Engine.Jobs.ResumeFlowJob
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

  describe "orphaned waiters" do
    import Ecto.Query

    defp make_stale(instance) do
      old = DateTime.add(DateTime.utc_now(), -10, :day) |> DateTime.truncate(:second)

      Repo.update_all(
        from(i in FlowInstance, where: i.id == ^instance.id),
        set: [updated_at: old]
      )
    end

    test "reaps a stale waiting instance with no pending resume job" do
      instance = insert(:flow_instance, status: "waiting")
      make_stale(instance)

      assert {:ok, %{stale_marked: n}} = CleanupJob.perform(%Oban.Job{args: %{}})
      assert n >= 1

      reloaded = Repo.get(FlowInstance, instance.id)
      assert reloaded.status == "failed"
      assert reloaded.exit_reason == "stale_no_resume_job"
    end

    test "leaves a stale waiting instance that still has a pending resume job" do
      instance = insert(:flow_instance, status: "waiting")
      make_stale(instance)

      {:ok, _job} =
        %{"instance_id" => instance.id, "node_id" => "w1", "trigger" => "timer_expired"}
        |> ResumeFlowJob.new(schedule_in: 3600)
        |> Oban.insert()

      assert {:ok, _} = CleanupJob.perform(%Oban.Job{args: %{}})
      assert Repo.get(FlowInstance, instance.id).status == "waiting"
    end
  end
end
