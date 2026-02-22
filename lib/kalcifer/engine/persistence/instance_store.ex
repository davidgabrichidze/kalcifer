defmodule Kalcifer.Engine.Persistence.InstanceStore do
  @moduledoc false

  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Repo

  def create_instance(attrs) do
    %FlowInstance{}
    |> FlowInstance.create_changeset(attrs)
    |> Repo.insert()
  end

  def get_instance(id) do
    Repo.get(FlowInstance, id)
  end

  def update_current_nodes(instance, node_ids) do
    instance
    |> FlowInstance.status_changeset(instance.status, %{current_nodes: node_ids})
    |> Repo.update()
  end

  def complete_instance(instance) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    instance
    |> FlowInstance.status_changeset("completed", %{
      completed_at: now,
      current_nodes: []
    })
    |> Repo.update()
  end

  def fail_instance(instance, reason) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    instance
    |> FlowInstance.status_changeset("failed", %{
      exit_reason: reason,
      exited_at: now,
      current_nodes: []
    })
    |> Repo.update()
  end
end
