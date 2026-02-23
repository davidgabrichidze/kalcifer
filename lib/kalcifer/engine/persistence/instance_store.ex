defmodule Kalcifer.Engine.Persistence.InstanceStore do
  @moduledoc false

  import Ecto.Query

  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Repo

  def create_instance(attrs, opts \\ []) do
    base =
      case Keyword.get(opts, :id) do
        nil -> %FlowInstance{}
        id -> %FlowInstance{id: id}
      end

    base
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

  def customer_active_in_flow?(flow_id, customer_id) do
    FlowInstance
    |> where([i], i.flow_id == ^flow_id)
    |> where([i], i.customer_id == ^customer_id)
    |> where([i], i.status in ["running", "waiting"])
    |> Repo.exists?()
  end

  def list_waiting_for_customer(customer_id) do
    FlowInstance
    |> where([i], i.customer_id == ^customer_id and i.status == "waiting")
    |> Repo.all()
  end

  def list_recoverable_instances do
    FlowInstance
    |> where([i], i.status in ["running", "waiting"])
    |> Repo.all()
  end

  def list_active_for_version(flow_id, version_number) do
    FlowInstance
    |> where([i], i.flow_id == ^flow_id)
    |> where([i], i.version_number == ^version_number)
    |> where([i], i.status in ["running", "waiting"])
    |> Repo.all()
  end

  def migrate_instance(instance, new_version_number) do
    old_version = instance.version_number

    instance
    |> FlowInstance.migration_changeset(new_version_number, old_version)
    |> Repo.update()
  end

  def exit_instance(instance, reason) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    instance
    |> FlowInstance.status_changeset("exited", %{
      exit_reason: reason,
      exited_at: now,
      current_nodes: []
    })
    |> Repo.update()
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
