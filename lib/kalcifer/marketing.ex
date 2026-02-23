defmodule Kalcifer.Marketing do
  @moduledoc false

  import Ecto.Query

  alias Kalcifer.Flows
  alias Kalcifer.Marketing.Journey
  alias Kalcifer.Repo

  # --- Journey CRUD ---

  def create_journey(tenant_id, attrs) do
    %Journey{}
    |> Journey.create_changeset(Map.put(attrs, :tenant_id, tenant_id))
    |> Repo.insert()
  end

  def get_journey(id) do
    Repo.get(Journey, id)
  end

  def get_journey!(id) do
    Repo.get!(Journey, id)
  end

  def get_journey_with_flow(id) do
    Journey
    |> Repo.get(id)
    |> Repo.preload(:flow)
  end

  def list_journeys(tenant_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    tag = Keyword.get(opts, :tag)

    Journey
    |> where(tenant_id: ^tenant_id)
    |> maybe_filter_status(status)
    |> maybe_filter_tag(tag)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def update_journey(%Journey{status: "draft"} = journey, attrs) do
    journey
    |> Journey.update_changeset(attrs)
    |> Repo.update()
  end

  def update_journey(%Journey{}, _attrs) do
    {:error, :journey_not_draft}
  end

  def delete_journey(%Journey{status: "draft"} = journey) do
    Repo.delete(journey)
  end

  def delete_journey(%Journey{}) do
    {:error, :journey_not_draft}
  end

  # --- Lifecycle ---

  def launch_journey(%Journey{} = journey) do
    Repo.transaction(fn ->
      flow = Flows.get_flow!(journey.flow_id)

      case Flows.activate_flow(flow) do
        {:ok, _activated_flow} ->
          journey
          |> Journey.status_changeset("active")
          |> Repo.update!()

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def pause_journey(%Journey{} = journey) do
    Repo.transaction(fn ->
      flow = Flows.get_flow!(journey.flow_id)

      case Flows.pause_flow(flow) do
        {:ok, _paused_flow} ->
          journey
          |> Journey.status_changeset("paused")
          |> Repo.update!()

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def resume_journey(%Journey{} = journey) do
    Repo.transaction(fn ->
      flow = Flows.get_flow!(journey.flow_id)

      case Flows.resume_flow(flow) do
        {:ok, _resumed_flow} ->
          journey
          |> Journey.status_changeset("active")
          |> Repo.update!()

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def archive_journey(%Journey{} = journey) do
    Repo.transaction(fn ->
      flow = Flows.get_flow!(journey.flow_id)

      case Flows.archive_flow(flow) do
        {:ok, _archived_flow} ->
          journey
          |> Journey.status_changeset("archived")
          |> Repo.update!()

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  # --- Private ---

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp maybe_filter_tag(query, nil), do: query
  defp maybe_filter_tag(query, tag), do: where(query, [j], ^tag in j.tags)
end
