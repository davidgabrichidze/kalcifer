defmodule Kalcifer.Analytics.Conversion do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Flows.Flow
  alias Kalcifer.Flows.FlowInstance

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversions" do
    field :customer_id, :string
    field :conversion_type, :string
    field :value, :float
    field :metadata, :map, default: %{}
    field :converted_at, :utc_datetime

    belongs_to :flow, Flow
    belongs_to :instance, FlowInstance

    timestamps(type: :utc_datetime)
  end

  def changeset(conversion, attrs) do
    conversion
    |> cast(attrs, [
      :flow_id,
      :instance_id,
      :customer_id,
      :conversion_type,
      :value,
      :metadata,
      :converted_at
    ])
    |> validate_required([:flow_id, :instance_id, :customer_id, :conversion_type, :converted_at])
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:instance_id)
  end
end
