defmodule KalciferWeb.InstanceController do
  use KalciferWeb, :controller

  import Ecto.Query

  alias Kalcifer.Flows.ExecutionStep
  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Repo

  action_fallback KalciferWeb.FallbackController

  def index(conn, %{"flow_id" => flow_id} = params) do
    tenant = conn.assigns.current_tenant

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
    tenant = conn.assigns.current_tenant

    case Repo.get(FlowInstance, id) do
      %{tenant_id: tid} = instance when tid == tenant.id ->
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

      _ ->
        {:error, :not_found}
    end
  end

  def timeline(conn, %{"id" => id}) do
    tenant = conn.assigns.current_tenant

    case Repo.get(FlowInstance, id) do
      %{tenant_id: tid} when tid == tenant.id ->
        steps =
          from(s in ExecutionStep,
            where: s.instance_id == ^id,
            order_by: [asc: s.started_at]
          )
          |> Repo.all()

        json(conn, %{data: Enum.map(steps, &serialize_step/1)})

      _ ->
        {:error, :not_found}
    end
  end

  def cancel(conn, %{"id" => id}) do
    tenant = conn.assigns.current_tenant

    case Repo.get(FlowInstance, id) do
      %{tenant_id: tid, status: status} = instance
      when tid == tenant.id and status in ["running", "waiting"] ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        changeset =
          FlowInstance.status_changeset(instance, "exited", %{
            exited_at: now,
            exit_reason: "cancelled_by_operator"
          })

        case Repo.update(changeset) do
          {:ok, updated} ->
            json(conn, %{data: serialize_instance(updated)})

          {:error, changeset} ->
            {:error, changeset}
        end

      %{tenant_id: tid} when tid == tenant.id ->
        conn |> put_status(:conflict) |> json(%{error: "instance not cancellable"})

      _ ->
        {:error, :not_found}
    end
  end

  defp apply_filters(query, params) do
    query
    |> maybe_filter_status(params)
    |> maybe_filter_customer(params)
    |> maybe_limit(params)
  end

  defp maybe_filter_status(query, %{"status" => status}) do
    from(i in query, where: i.status == ^status)
  end

  defp maybe_filter_status(query, _), do: query

  defp maybe_filter_customer(query, %{"customer_id" => cid}) do
    from(i in query, where: i.customer_id == ^cid)
  end

  defp maybe_filter_customer(query, _), do: query

  defp maybe_limit(query, %{"limit" => limit}) do
    from(i in query, limit: ^limit)
  end

  defp maybe_limit(query, _), do: from(i in query, limit: 50)

  defp serialize_instance(instance) do
    %{
      id: instance.id,
      flow_id: instance.flow_id,
      customer_id: instance.customer_id,
      status: instance.status,
      version_number: instance.version_number,
      current_nodes: instance.current_nodes,
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
      output: step.output
    }
  end
end
