defmodule Kalcifer.Engine.Jobs.ResumeFlowJobTest do
  use Kalcifer.DataCase, async: false

  alias Kalcifer.Engine.Jobs.ResumeFlowJob

  describe "perform/1" do
    test "snoozes when FlowServer is not alive" do
      # Oban serializes args as JSON (string keys)
      args = %{
        "instance_id" => Ecto.UUID.generate(),
        "node_id" => "wait_1",
        "trigger" => "timer_expired"
      }

      # When FlowServer is dead, job should snooze to retry later
      # (gives RecoveryManager time to restart the process)
      assert {:snooze, 30} = ResumeFlowJob.perform(%Oban.Job{args: args})
    end
  end
end
