defmodule Kalcifer.Journeys.JourneyVersion do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Journeys.Journey
  alias Kalcifer.Journeys.JourneyGraph

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(draft published deprecated rolled_back)

  schema "journey_versions" do
    field :version_number, :integer
    field :graph, :map
    field :status, :string, default: "draft"
    field :node_mapping, :map
    field :migration_strategy, :string
    field :migration_config, :map
    field :changelog, :string
    field :published_by, :binary_id
    field :published_at, :utc_datetime

    belongs_to :journey, Journey

    timestamps(type: :utc_datetime)
  end

  def create_changeset(version, attrs) do
    version
    |> cast(attrs, [:journey_id, :version_number, :graph, :changelog])
    |> validate_required([:journey_id, :version_number, :graph])
    |> put_change(:status, "draft")
    |> unique_constraint([:journey_id, :version_number])
    |> foreign_key_constraint(:journey_id)
  end

  def update_changeset(version, attrs) do
    version
    |> cast(attrs, [:graph, :changelog])
    |> validate_required([:graph])
  end

  def publish_changeset(version) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    version
    |> change(status: "published", published_at: now)
    |> validate_graph()
  end

  def statuses, do: @statuses

  defp validate_graph(changeset) do
    graph = get_field(changeset, :graph)

    case JourneyGraph.validate(graph) do
      :ok ->
        changeset

      {:error, errors} ->
        Enum.reduce(errors, changeset, fn error, cs ->
          add_error(cs, :graph, error)
        end)
    end
  end
end
