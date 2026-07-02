defmodule Kalcifer.Channels.Delivery do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Tenants.Tenant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending sent delivered bounced failed)

  # delivered / bounced / failed are terminal — once reached, a later
  # (often out-of-order) provider callback must not move the delivery to a
  # different status, or a bounced address could read as delivered.
  @terminal_statuses ~w(delivered bounced failed)

  schema "deliveries" do
    field :channel, :string
    field :recipient, :map
    field :message, :map, default: %{}
    field :provider, :string
    field :provider_message_id, :string
    field :status, :string, default: "pending"
    field :step_id, :binary_id
    field :error, :string
    field :events, {:array, :map}, default: []
    field :sent_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :failed_at, :utc_datetime

    belongs_to :instance, FlowInstance
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime)
  end

  def create_changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :channel,
      :recipient,
      :message,
      :provider,
      :step_id,
      :instance_id,
      :tenant_id
    ])
    |> validate_required([:channel, :recipient, :instance_id, :tenant_id])
    |> put_change(:status, "pending")
    |> foreign_key_constraint(:instance_id)
    |> foreign_key_constraint(:tenant_id)
  end

  def status_changeset(delivery, new_status, attrs \\ %{}) do
    delivery
    |> cast(attrs, [:provider_message_id, :error, :sent_at, :delivered_at, :failed_at])
    |> put_change(:status, new_status)
    |> validate_inclusion(:status, @statuses)
    |> validate_terminal_transition(delivery.status, new_status)
  end

  # Idempotent same-status writes are allowed (e.g. re-applying "delivered").
  defp validate_terminal_transition(changeset, same, same), do: changeset

  defp validate_terminal_transition(changeset, from, _to) when from in @terminal_statuses do
    add_error(changeset, :status, "cannot transition out of terminal status #{from}")
  end

  defp validate_terminal_transition(changeset, _from, _to), do: changeset

  def statuses, do: @statuses

  def terminal_statuses, do: @terminal_statuses
end
