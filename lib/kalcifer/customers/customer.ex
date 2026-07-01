defmodule Kalcifer.Customers.Customer do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Tenants.Tenant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "customers" do
    field :external_id, :string
    field :email, :string
    field :phone, :string
    field :name, :string
    field :properties, :map, default: %{}
    field :tags, {:array, :string}, default: []
    field :preferences, :map, default: %{}
    field :last_seen_at, :utc_datetime

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime)
  end

  # Properties guardrails: arbitrary JSON is accepted, but bounded so a
  # single customer cannot blow up row size or query performance.
  @max_properties 100
  @max_key_length 100
  @max_depth 3
  @max_encoded_bytes 65_536

  def create_changeset(customer, attrs) do
    customer
    |> cast(attrs, [
      :external_id,
      :email,
      :phone,
      :name,
      :properties,
      :tags,
      :preferences,
      :tenant_id
    ])
    |> validate_required([:external_id, :tenant_id])
    |> validate_properties()
    |> unique_constraint(:external_id, name: :customers_tenant_id_external_id_index)
    |> foreign_key_constraint(:tenant_id)
  end

  def update_changeset(customer, attrs) do
    customer
    |> cast(attrs, [:email, :phone, :name, :properties, :preferences, :last_seen_at])
    |> validate_properties()
  end

  defp validate_properties(changeset) do
    validate_change(changeset, :properties, fn :properties, properties ->
      cond do
        is_struct(properties) ->
          [properties: "must be a plain map"]

        map_size(properties) > @max_properties ->
          [properties: "must have at most #{@max_properties} top-level keys"]

        not valid_keys?(properties) ->
          [properties: "keys must be strings of at most #{@max_key_length} characters"]

        not valid_value?(properties, @max_depth) ->
          [
            properties:
              "values must be JSON scalars, lists or maps nested at most #{@max_depth} levels"
          ]

        encoded_size(properties) > @max_encoded_bytes ->
          [properties: "encoded size must not exceed #{@max_encoded_bytes} bytes"]

        true ->
          []
      end
    end)
  end

  defp valid_keys?(map) do
    Enum.all?(map, fn {key, _value} ->
      is_binary(key) and String.length(key) <= @max_key_length
    end)
  end

  defp valid_value?(_value, depth) when depth < 0, do: false

  defp valid_value?(map, depth) when is_map(map) and not is_struct(map) do
    Enum.all?(map, fn {key, value} -> is_binary(key) and valid_value?(value, depth - 1) end)
  end

  defp valid_value?(list, depth) when is_list(list) do
    Enum.all?(list, &valid_value?(&1, depth - 1))
  end

  defp valid_value?(value, _depth)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: true

  defp valid_value?(_value, _depth), do: false

  defp encoded_size(properties) do
    properties |> Jason.encode_to_iodata!() |> IO.iodata_length()
  end
end
