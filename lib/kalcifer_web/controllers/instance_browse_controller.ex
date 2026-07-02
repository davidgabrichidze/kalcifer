defmodule KalciferWeb.InstanceBrowseController do
  @moduledoc """
  Unauthenticated instance browsing for the dev frontend.
  Uses Demo Tenant fallback (same pattern as FlowController).
  """
  use KalciferWeb, :controller

  import Ecto.Query

  alias Kalcifer.Flows.{ExecutionStep, FlowInstance}
  alias Kalcifer.Repo

  def index(conn, %{"flow_id" => flow_id} = params) do
    tenant = KalciferWeb.TenantResolver.resolve(conn)

    query =
      from(i in FlowInstance,
        where: i.flow_id == ^flow_id and i.tenant_id == ^tenant.id,
        order_by: [desc: i.entered_at]
      )

    query = apply_filters(query, params)
    instances = Repo.all(query)
    json(conn, %{data: Enum.map(instances, &serialize_instance/1)})
  end

  def show(conn, %{"id" => id}) do
    tenant = KalciferWeb.TenantResolver.resolve(conn)

    case Repo.get(FlowInstance, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      %{tenant_id: tid} when tid != tenant.id ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      instance ->
        steps =
          from(s in ExecutionStep,
            where: s.instance_id == ^id,
            order_by: [asc: s.started_at]
          )
          |> Repo.all()

        json(conn, %{
          data: serialize_instance(instance),
          steps: Enum.map(steps, &serialize_step/1)
        })
    end
  end

  def timeline(conn, %{"id" => id}) do
    tenant = KalciferWeb.TenantResolver.resolve(conn)

    case Repo.get(FlowInstance, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      %{tenant_id: tid} when tid != tenant.id ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      _instance ->
        steps =
          from(s in ExecutionStep,
            where: s.instance_id == ^id,
            order_by: [asc: s.started_at]
          )
          |> Repo.all()

        json(conn, %{data: Enum.map(steps, &serialize_step/1)})
    end
  end

  defp apply_filters(query, params) do
    query
    |> maybe_filter_status(params)
    |> maybe_filter_dry_run(params)
    |> maybe_limit(params)
  end

  defp maybe_filter_status(query, %{"status" => status}),
    do: from(i in query, where: i.status == ^status)

  defp maybe_filter_status(query, _), do: query

  defp maybe_filter_dry_run(query, %{"dry_run" => "true"}),
    do: from(i in query, where: i.dry_run == true)

  defp maybe_filter_dry_run(query, %{"dry_run" => "false"}),
    do: from(i in query, where: i.dry_run == false)

  defp maybe_filter_dry_run(query, _), do: query

  @default_limit 50
  @max_limit 200

  defp maybe_limit(query, %{"limit" => limit}) when is_binary(limit) do
    case Integer.parse(limit) do
      {n, _} -> from(i in query, limit: ^clamp_limit(n))
      :error -> from(i in query, limit: ^@default_limit)
    end
  end

  defp maybe_limit(query, _), do: from(i in query, limit: ^@default_limit)

  # Keep the limit sane: a negative value makes Postgres error (500) and an
  # unbounded value lets a caller scan the whole table.
  defp clamp_limit(n), do: n |> max(1) |> min(@max_limit)

  defp serialize_instance(instance) do
    %{
      id: instance.id,
      flow_id: instance.flow_id,
      customer_id: instance.customer_id,
      status: instance.status,
      version_number: instance.version_number,
      current_nodes: instance.current_nodes,
      dry_run: instance.dry_run,
      entered_at: instance.entered_at,
      completed_at: instance.completed_at,
      exited_at: instance.exited_at,
      exit_reason: instance.exit_reason
    }
  end

  defp serialize_step(step) do
    %{
      id: step.id,
      node_id: step.node_id,
      node_type: step.node_type,
      status: step.status,
      started_at: step.started_at,
      completed_at: step.completed_at,
      output: step.output,
      error: step.error
    }
  end
end
