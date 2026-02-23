defmodule Kalcifer.Analytics.NodeStats do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Flows.Flow

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "node_stats" do
    field :version_number, :integer
    field :node_id, :string
    field :date, :date
    field :executed, :integer, default: 0
    field :completed, :integer, default: 0
    field :failed, :integer, default: 0
    field :branch_counts, :map, default: %{}

    belongs_to :flow, Flow

    timestamps(type: :utc_datetime)
  end

  def changeset(stats, attrs) do
    stats
    |> cast(attrs, [
      :flow_id,
      :version_number,
      :node_id,
      :date,
      :executed,
      :completed,
      :failed,
      :branch_counts
    ])
    |> validate_required([:flow_id, :version_number, :node_id, :date])
    |> unique_constraint([:flow_id, :version_number, :node_id, :date])
  end
end
