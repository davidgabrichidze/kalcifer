defmodule Kalcifer.Repo.Migrations.UniqueActiveCustomerIndex do
  use Ecto.Migration

  @moduledoc """
  Replaces the non-unique active-customer index with a UNIQUE partial
  index so concurrent triggers for the same (flow, customer) can't both
  create an active instance (TOCTOU race). Scoped to non-dry-run
  instances — simulations are exempt.
  """

  def up do
    # Exit any pre-existing duplicate active instances, keeping the newest,
    # so the unique index can be created.
    execute("""
    WITH ranked AS (
      SELECT id,
             ROW_NUMBER() OVER (
               PARTITION BY flow_id, customer_id
               ORDER BY entered_at DESC, inserted_at DESC
             ) AS rn
      FROM flow_instances
      WHERE status IN ('running', 'waiting') AND dry_run = false
    )
    UPDATE flow_instances
    SET status = 'exited', exit_reason = 'deduped_active_instance'
    WHERE id IN (SELECT id FROM ranked WHERE rn > 1)
    """)

    drop_if_exists index(:flow_instances, [:flow_id, :customer_id],
                     name: :flow_instances_active_customer
                   )

    create unique_index(
             :flow_instances,
             [:flow_id, :customer_id],
             where: "status IN ('running', 'waiting') AND dry_run = false",
             name: :flow_instances_active_customer
           )
  end

  def down do
    drop_if_exists index(:flow_instances, [:flow_id, :customer_id],
                     name: :flow_instances_active_customer
                   )

    create index(
             :flow_instances,
             [:flow_id, :customer_id],
             where: "status IN ('running', 'waiting')",
             name: :flow_instances_active_customer
           )
  end
end
