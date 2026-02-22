defmodule Kalcifer.Journeys do
  @moduledoc false

  import Ecto.Query

  alias Kalcifer.Journeys.Journey
  alias Kalcifer.Journeys.JourneyVersion
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

  def list_journeys(tenant_id, opts \\ []) do
    status = Keyword.get(opts, :status)

    Journey
    |> where(tenant_id: ^tenant_id)
    |> maybe_filter_status(status)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def update_journey(%Journey{status: "draft"} = journey, attrs) do
    journey
    |> Journey.update_changeset(attrs)
    |> Repo.update()
  end

  def update_journey(%Journey{}, _attrs) do
    {:error, :not_draft}
  end

  def delete_journey(%Journey{status: "draft"} = journey) do
    Repo.delete(journey)
  end

  def delete_journey(%Journey{}) do
    {:error, :not_draft}
  end

  # --- Lifecycle ---

  def activate_journey(%Journey{} = journey) do
    Repo.transaction(fn ->
      journey.id
      |> get_latest_draft_version()
      |> do_activate(journey)
    end)
  end

  defp do_activate(nil, _journey), do: Repo.rollback(:no_draft_version)

  defp do_activate(version, journey) do
    case publish_version(version) do
      {:ok, published_version} ->
        journey
        |> Journey.status_changeset("active")
        |> Repo.update!()
        |> Journey.active_version_changeset(published_version.id)
        |> Repo.update!()

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  def pause_journey(%Journey{} = journey) do
    journey
    |> Journey.status_changeset("paused")
    |> Repo.update()
  end

  def resume_journey(%Journey{} = journey) do
    journey
    |> Journey.status_changeset("active")
    |> Repo.update()
  end

  def archive_journey(%Journey{} = journey) do
    journey
    |> Journey.status_changeset("archived")
    |> Repo.update()
  end

  # --- Versions ---

  def create_version(%Journey{} = journey, attrs) do
    next_number = next_version_number(journey.id)

    %JourneyVersion{}
    |> JourneyVersion.create_changeset(
      Map.merge(attrs, %{journey_id: journey.id, version_number: next_number})
    )
    |> Repo.insert()
  end

  def get_version(journey_id, version_number) do
    Repo.get_by(JourneyVersion, journey_id: journey_id, version_number: version_number)
  end

  def list_versions(journey_id) do
    JourneyVersion
    |> where(journey_id: ^journey_id)
    |> order_by(asc: :version_number)
    |> Repo.all()
  end

  def publish_version(%JourneyVersion{status: "draft"} = version) do
    version
    |> JourneyVersion.publish_changeset()
    |> Repo.update()
  end

  def publish_version(%JourneyVersion{}) do
    {:error, :not_draft}
  end

  # --- Private ---

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp next_version_number(journey_id) do
    JourneyVersion
    |> where(journey_id: ^journey_id)
    |> select([v], max(v.version_number))
    |> Repo.one()
    |> case do
      nil -> 1
      n -> n + 1
    end
  end

  defp get_latest_draft_version(journey_id) do
    JourneyVersion
    |> where(journey_id: ^journey_id)
    |> where(status: "draft")
    |> order_by(desc: :version_number)
    |> limit(1)
    |> Repo.one()
  end
end
