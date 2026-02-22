defmodule Kalcifer.Engine.Persistence.StepStore do
  @moduledoc false

  alias Kalcifer.Flows.ExecutionStep
  alias Kalcifer.Repo

  def record_step_start(instance_id, node, version_number) do
    %ExecutionStep{}
    |> ExecutionStep.create_changeset(%{
      instance_id: instance_id,
      node_id: node["id"],
      node_type: node["type"],
      version_number: version_number,
      input: node["config"] || %{}
    })
    |> Repo.insert()
  end

  def record_step_complete(step, output) do
    step
    |> ExecutionStep.complete_changeset(%{output: output})
    |> Repo.update()
  end

  def record_step_fail(step, error) do
    step
    |> ExecutionStep.fail_changeset(error)
    |> Repo.update()
  end
end
