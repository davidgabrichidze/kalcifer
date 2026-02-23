defmodule Kalcifer.Engine.Persistence.StepStore do
  @moduledoc false

  import Ecto.Query

  alias Kalcifer.Flows.ExecutionStep
  alias Kalcifer.Flows.FlowInstance
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

  def count_channel_steps_for_customer(customer_id, channel_types, since) do
    ExecutionStep
    |> join(:inner, [s], i in FlowInstance, on: s.instance_id == i.id)
    |> where([s, i], i.customer_id == ^customer_id)
    |> where([s, _i], s.node_type in ^channel_types)
    |> where([s, _i], s.status == "completed")
    |> where([s, _i], s.completed_at >= ^since)
    |> Repo.aggregate(:count)
  end
end
