defmodule Kalcifer.Marketing.Journey do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Flows.Flow
  alias Kalcifer.Tenants.Tenant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(draft active paused archived)
  @valid_transitions %{
    "draft" => ["active"],
    "active" => ["paused", "archived"],
    "paused" => ["active", "archived"],
    "archived" => []
  }

  schema "journeys" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "draft"
    field :goal_config, :map, default: %{}
    field :schedule, :map, default: %{}
    field :audience_criteria, :map, default: %{}
    field :tags, {:array, :string}, default: []

    belongs_to :flow, Flow
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime)
  end

  def create_changeset(journey, attrs) do
    journey
    |> cast(attrs, [
      :name,
      :description,
      :tenant_id,
      :flow_id,
      :goal_config,
      :schedule,
      :audience_criteria,
      :tags
    ])
    |> validate_required([:name, :tenant_id, :flow_id])
    |> put_change(:status, "draft")
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:flow_id)
  end

  def update_changeset(journey, attrs) do
    journey
    |> cast(attrs, [:name, :description, :goal_config, :schedule, :audience_criteria, :tags])
    |> validate_required([:name])
  end

  def status_changeset(journey, new_status) do
    journey
    |> change(status: new_status)
    |> validate_inclusion(:status, @statuses)
    |> validate_transition(journey.status, new_status)
  end

  def valid_transitions, do: @valid_transitions

  defp validate_transition(changeset, from, to) do
    allowed = Map.get(@valid_transitions, from, [])

    if to in allowed do
      changeset
    else
      add_error(changeset, :status, "cannot transition from #{from} to #{to}")
    end
  end
end
