defmodule Kalcifer.Bugs.ResumeJobDeadProcessTest do
  @moduledoc """
  C3: ResumeFlowJob returns :ok when the FlowServer process is dead.
  Oban marks the job as succeeded and discards it. RecoveryManager only
  runs at boot, so the customer is permanently stuck in the wait node.
  The job should snooze or error to trigger a retry.
  """
  use Kalcifer.DataCase, async: false

  alias Kalcifer.Engine.Jobs.ResumeFlowJob

  @tag :known_bug
  test "perform returns snooze or error when FlowServer process is not alive" do
    # Create a job with a non-existent instance (no FlowServer running)
    instance_id = Ecto.UUID.generate()

    job = %Oban.Job{
      args: %{
        "instance_id" => instance_id,
        "node_id" => "wait_1",
        "trigger" => "timer_expired"
      }
    }

    result = ResumeFlowJob.perform(job)

    # BUG: Currently returns :ok, which tells Oban the job succeeded.
    # Should return {:snooze, _} or {:error, _} to trigger retry.
    assert result != :ok,
           "BUG: ResumeFlowJob returned :ok for dead process — customer will be stuck forever"
  end
end
