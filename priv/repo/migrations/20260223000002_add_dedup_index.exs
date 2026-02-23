defmodule Kalcifer.Repo.Migrations.AddDedupIndex do
  use Ecto.Migration

  def change do
    create index(
             :flow_instances,
             [:flow_id, :customer_id],
             where: "status IN ('running', 'waiting')",
             name: :flow_instances_active_customer
           )
  end
end
