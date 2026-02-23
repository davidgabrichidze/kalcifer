defmodule Kalcifer.Analytics.FlowStats do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Flows.Flow

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "flow_stats" do
    field :version_number, :integer
    field :date, :date
    field :entered, :integer, default: 0
    field :completed, :integer, default: 0
    field :failed, :integer, default: 0
    field :exited, :integer, default: 0
    field :avg_completion_time_seconds, :float

    belongs_to :flow, Flow

    timestamps(type: :utc_datetime)
  end

  def changeset(stats, attrs) do
    stats
    |> cast(attrs, [
      :flow_id,
      :version_number,
      :date,
      :entered,
      :completed,
      :failed,
      :exited,
      :avg_completion_time_seconds
    ])
    |> validate_required([:flow_id, :version_number, :date])
    |> unique_constraint([:flow_id, :version_number, :date])
  end
end
