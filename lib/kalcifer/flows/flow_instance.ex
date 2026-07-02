defmodule Kalcifer.Flows.FlowInstance do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Flows.Flow
  alias Kalcifer.Tenants.Tenant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(running waiting paused completed failed exited)

  # Valid status transitions: {from, to}
  @valid_transitions [
    {"running", "waiting"},
    {"running", "paused"},
    {"running", "completed"},
    {"running", "failed"},
    {"running", "exited"},
    {"waiting", "running"},
    {"waiting", "paused"},
    {"waiting", "completed"},
    {"waiting", "failed"},
    {"waiting", "exited"},
    {"paused", "running"},
    {"paused", "exited"}
  ]

  schema "flow_instances" do
    field :version_number, :integer
    field :customer_id, :string
    field :status, :string, default: "running"
    field :current_nodes, {:array, :string}, default: []
    field :context, :map, default: %{}
    field :entered_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :exited_at, :utc_datetime
    field :failed_at, :utc_datetime
    field :exit_reason, :string
    field :dry_run, :boolean, default: false
    field :migrated_from_version, :integer
    field :migrated_at, :utc_datetime

    belongs_to :flow, Flow
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime)
  end

  def create_changeset(instance, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    instance
    |> cast(attrs, [:flow_id, :version_number, :customer_id, :tenant_id, :current_nodes, :dry_run])
    |> validate_required([:flow_id, :version_number, :customer_id, :tenant_id])
    |> put_change(:status, "running")
    |> put_change(:entered_at, now)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:flow_id, :customer_id],
      name: :flow_instances_active_customer,
      message: "customer already active in this flow"
    )
  end

  def status_changeset(instance, new_status, attrs \\ %{}) do
    instance
    |> cast(attrs, [:completed_at, :exited_at, :failed_at, :exit_reason, :current_nodes, :context])
    |> put_change(:status, new_status)
    |> maybe_stamp_failed_at(instance, new_status)
    |> validate_inclusion(:status, @statuses)
    |> validate_transition(instance.status, new_status)
  end

  # Stamp failed_at once, on the transition into "failed", unless the caller
  # supplied one. Analytics attributes failures by this timestamp, so it must
  # not drift when the row is later touched.
  defp maybe_stamp_failed_at(changeset, %{status: "failed"}, "failed"), do: changeset

  defp maybe_stamp_failed_at(changeset, _instance, "failed") do
    case get_change(changeset, :failed_at) do
      nil -> put_change(changeset, :failed_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end

  defp maybe_stamp_failed_at(changeset, _instance, _new_status), do: changeset

  # Same-status "transition" is a no-op (e.g. update_current_nodes while running)
  defp validate_transition(changeset, same, same), do: changeset

  defp validate_transition(changeset, from, to) do
    if {from, to} in @valid_transitions do
      changeset
    else
      add_error(changeset, :status, "invalid transition from #{from} to #{to}")
    end
  end

  def migration_changeset(instance, new_version_number, old_version_number) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    instance
    |> change(
      version_number: new_version_number,
      migrated_from_version: old_version_number,
      migrated_at: now
    )
  end

  def statuses, do: @statuses
end
