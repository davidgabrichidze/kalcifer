defmodule Kalcifer.Engine.Jobs.ResumeFlowJobTest do
  use Kalcifer.DataCase, async: false

  alias Kalcifer.Engine.Jobs.ResumeFlowJob

  describe "perform/1" do
    test "succeeds when FlowServer is not alive" do
      # Oban serializes args as JSON (string keys)
      args = %{
        "instance_id" => Ecto.UUID.generate(),
        "node_id" => "wait_1",
        "trigger" => "timer_expired"
      }

      assert :ok = ResumeFlowJob.perform(%Oban.Job{args: args})
    end
  end
end
