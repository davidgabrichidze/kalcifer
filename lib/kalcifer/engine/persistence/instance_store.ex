defmodule Kalcifer.Engine.Persistence.InstanceStore do
  @moduledoc false

  alias Kalcifer.Journeys.JourneyInstance
  alias Kalcifer.Repo

  def create_instance(attrs) do
    %JourneyInstance{}
    |> JourneyInstance.create_changeset(attrs)
    |> Repo.insert()
  end

  def get_instance(id) do
    Repo.get(JourneyInstance, id)
  end

  def update_current_nodes(instance, node_ids) do
    instance
    |> JourneyInstance.status_changeset(instance.status, %{current_nodes: node_ids})
    |> Repo.update()
  end

  def complete_instance(instance) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    instance
    |> JourneyInstance.status_changeset("completed", %{
      completed_at: now,
      current_nodes: []
    })
    |> Repo.update()
  end

  def fail_instance(instance, reason) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    instance
    |> JourneyInstance.status_changeset("failed", %{
      exit_reason: reason,
      exited_at: now,
      current_nodes: []
    })
    |> Repo.update()
  end
end
