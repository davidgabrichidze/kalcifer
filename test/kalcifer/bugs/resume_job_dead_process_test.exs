defmodule Kalcifer.Bugs.ResumeJobDeadProcessTest do
  @moduledoc """
  C3: Regression test for ResumeFlowJob dead process handling.
  ResumeFlowJob returns {:snooze, 30} when FlowServer is not alive,
  so Oban retries after RecoveryManager has a chance to restore it.
  """
  use Kalcifer.DataCase, async: false

  alias Kalcifer.Engine.Jobs.ResumeFlowJob

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

    assert result != :ok,
           "ResumeFlowJob returned :ok for dead process — customer will be stuck forever"
  end
end
