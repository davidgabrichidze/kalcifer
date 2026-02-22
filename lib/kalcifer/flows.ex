defmodule Kalcifer.Flows do
  @moduledoc false

  import Ecto.Query

  alias Kalcifer.Flows.Flow
  alias Kalcifer.Flows.FlowVersion
  alias Kalcifer.Repo

  # --- Flow CRUD ---

  def create_flow(tenant_id, attrs) do
    %Flow{}
    |> Flow.create_changeset(Map.put(attrs, :tenant_id, tenant_id))
    |> Repo.insert()
  end

  def get_flow(id) do
    Repo.get(Flow, id)
  end

  def get_flow!(id) do
    Repo.get!(Flow, id)
  end

  def list_flows(tenant_id, opts \\ []) do
    status = Keyword.get(opts, :status)

    Flow
    |> where(tenant_id: ^tenant_id)
    |> maybe_filter_status(status)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def update_flow(%Flow{status: "draft"} = flow, attrs) do
    flow
    |> Flow.update_changeset(attrs)
    |> Repo.update()
  end

  def update_flow(%Flow{}, _attrs) do
    {:error, :not_draft}
  end

  def delete_flow(%Flow{status: "draft"} = flow) do
    Repo.delete(flow)
  end

  def delete_flow(%Flow{}) do
    {:error, :not_draft}
  end

  # --- Lifecycle ---

  def activate_flow(%Flow{} = flow) do
    Repo.transaction(fn ->
      flow.id
      |> get_latest_draft_version()
      |> do_activate(flow)
    end)
  end

  defp do_activate(nil, _flow), do: Repo.rollback(:no_draft_version)

  defp do_activate(version, flow) do
    case publish_version(version) do
      {:ok, published_version} ->
        flow
        |> Flow.status_changeset("active")
        |> Repo.update!()
        |> Flow.active_version_changeset(published_version.id)
        |> Repo.update!()

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  def pause_flow(%Flow{} = flow) do
    flow
    |> Flow.status_changeset("paused")
    |> Repo.update()
  end

  def resume_flow(%Flow{} = flow) do
    flow
    |> Flow.status_changeset("active")
    |> Repo.update()
  end

  def archive_flow(%Flow{} = flow) do
    flow
    |> Flow.status_changeset("archived")
    |> Repo.update()
  end

  # --- Versions ---

  def create_version(%Flow{} = flow, attrs) do
    next_number = next_version_number(flow.id)

    %FlowVersion{}
    |> FlowVersion.create_changeset(
      Map.merge(attrs, %{flow_id: flow.id, version_number: next_number})
    )
    |> Repo.insert()
  end

  def get_version(flow_id, version_number) do
    Repo.get_by(FlowVersion, flow_id: flow_id, version_number: version_number)
  end

  def list_versions(flow_id) do
    FlowVersion
    |> where(flow_id: ^flow_id)
    |> order_by(asc: :version_number)
    |> Repo.all()
  end

  def publish_version(%FlowVersion{status: "draft"} = version) do
    version
    |> FlowVersion.publish_changeset()
    |> Repo.update()
  end

  def publish_version(%FlowVersion{}) do
    {:error, :not_draft}
  end

  # --- Private ---

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp next_version_number(flow_id) do
    FlowVersion
    |> where(flow_id: ^flow_id)
    |> select([v], max(v.version_number))
    |> Repo.one()
    |> case do
      nil -> 1
      n -> n + 1
    end
  end

  defp get_latest_draft_version(flow_id) do
    FlowVersion
    |> where(flow_id: ^flow_id)
    |> where(status: "draft")
    |> order_by(desc: :version_number)
    |> limit(1)
    |> Repo.one()
  end
end
