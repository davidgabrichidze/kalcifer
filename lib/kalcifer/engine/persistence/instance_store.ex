defmodule Kalcifer.Engine.Persistence.InstanceStore do
  @moduledoc false

  import Ecto.Query

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

  def persist_waiting(instance, current_nodes, context) do
    instance
    |> FlowInstance.status_changeset("waiting", %{
      current_nodes: current_nodes,
      context: context
    })
    |> Repo.update()
  end

  def list_recoverable_instances do
    FlowInstance
    |> where([i], i.status in ["running", "waiting"])
    |> Repo.all()
  end

  def mark_crashed(instance) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    instance
    |> FlowInstance.status_changeset("failed", %{
      exit_reason: "server_crashed",
      exited_at: now,
      current_nodes: []
    })
    |> Repo.update()
  end
end
