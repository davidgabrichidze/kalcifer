defmodule Kalcifer.Flows.ExecutionStep do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Flows.FlowInstance

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(started completed failed skipped)

  schema "execution_steps" do
    field :node_id, :string
    field :node_type, :string
    field :version_number, :integer
    field :status, :string, default: "started"
    field :input, :map
    field :output, :map
    field :error, :map
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :instance, FlowInstance

    timestamps(type: :utc_datetime)
  end

  def create_changeset(step, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    step
    |> cast(attrs, [:instance_id, :node_id, :node_type, :version_number, :input])
    |> validate_required([:instance_id, :node_id, :node_type, :version_number])
    |> put_change(:status, "started")
    |> put_change(:started_at, now)
    |> foreign_key_constraint(:instance_id)
  end

  def complete_changeset(step, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    step
    |> cast(attrs, [:output, :error])
    |> put_change(:status, "completed")
    |> put_change(:completed_at, now)
  end

  def fail_changeset(step, error) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    step
    |> change(status: "failed", error: error, completed_at: now)
  end

  def statuses, do: @statuses
end
