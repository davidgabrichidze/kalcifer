defmodule Kalcifer.Flows.FlowInstance do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Flows.Flow
  alias Kalcifer.Tenants.Tenant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(running waiting paused completed failed exited)

  schema "flow_instances" do
    field :version_number, :integer
    field :customer_id, :string
    field :status, :string, default: "running"
    field :current_nodes, {:array, :string}, default: []
    field :context, :map, default: %{}
    field :entered_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :exited_at, :utc_datetime
    field :exit_reason, :string
    field :migrated_from_version, :integer
    field :migrated_at, :utc_datetime

    belongs_to :flow, Flow
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime)
  end

  def create_changeset(instance, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    instance
    |> cast(attrs, [:flow_id, :version_number, :customer_id, :tenant_id, :current_nodes])
    |> validate_required([:flow_id, :version_number, :customer_id, :tenant_id])
    |> put_change(:status, "running")
    |> put_change(:entered_at, now)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:tenant_id)
  end

  def status_changeset(instance, new_status, attrs \\ %{}) do
    instance
    |> cast(attrs, [:completed_at, :exited_at, :exit_reason, :current_nodes, :context])
    |> put_change(:status, new_status)
    |> validate_inclusion(:status, @statuses)
  end

  def statuses, do: @statuses
end
