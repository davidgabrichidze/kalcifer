defmodule Kalcifer.Flows.Flow do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Flows.FlowVersion
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

  schema "flows" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "draft"
    field :active_version_id, :binary_id
    field :entry_config, :map, default: %{}
    field :exit_criteria, :map, default: %{}
    field :frequency_cap, :map, default: %{}

    belongs_to :tenant, Tenant
    has_many :versions, FlowVersion

    timestamps(type: :utc_datetime)
  end

  def create_changeset(flow, attrs) do
    flow
    |> cast(attrs, [
      :name,
      :description,
      :tenant_id,
      :entry_config,
      :exit_criteria,
      :frequency_cap
    ])
    |> validate_required([:name, :tenant_id])
    |> put_change(:status, "draft")
    |> foreign_key_constraint(:tenant_id)
  end

  def update_changeset(flow, attrs) do
    flow
    |> cast(attrs, [:name, :description, :entry_config, :exit_criteria, :frequency_cap])
    |> validate_required([:name])
  end

  def status_changeset(flow, new_status) do
    flow
    |> change(status: new_status)
    |> validate_inclusion(:status, @statuses)
    |> validate_transition(flow.status, new_status)
  end

  def active_version_changeset(flow, version_id) do
    flow
    |> change(active_version_id: version_id)
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
