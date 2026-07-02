defmodule Kalcifer.Repo.Migrations.AddEngineHotpathIndexes do
  use Ecto.Migration

  @moduledoc """
  Indexes for two per-request engine hot paths that previously fell back
  to sequential scans:

  - EventRouter.list_waiting_for_customer runs on every inbound event; the
    only usable index was tenant-only.
  - FlowTrigger's frequency-cap query joins execution_steps by node_type/
    status/completed_at with no supporting index.
  """

  def change do
    # EventRouter: waiting instances for a (tenant, customer)
    create index(:flow_instances, [:tenant_id, :customer_id],
             where: "status = 'waiting'",
             name: :flow_instances_waiting_customer
           )

    # Frequency cap: completed channel steps by type and time
    create index(:execution_steps, [:node_type, :completed_at],
             where: "status = 'completed'",
             name: :execution_steps_completed_channel
           )

    # Frequency cap joins flow_instances by customer_id (any status)
    create index(:flow_instances, [:customer_id], name: :flow_instances_customer_id)
  end
end
