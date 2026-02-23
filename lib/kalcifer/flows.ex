defmodule Kalcifer.Flows do
  @moduledoc false

  import Ecto.Query

  alias Kalcifer.Flows.Flow
  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Flows.FlowVersion
  alias Kalcifer.Repo
  alias Kalcifer.Versioning.Migrator

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

  # --- Version Migration ---

  def migrate_flow_version(%Flow{} = flow, new_version_number, strategy \\ "new_entries_only") do
    new_version = get_version(flow.id, new_version_number)
    old_version = get_active_version(flow)

    with {:ok, _} <- validate_versions(new_version, old_version),
         {:ok, {old_vn, new_vn}} <- do_version_transition(flow, old_version, new_version) do
      Migrator.migrate(flow.id, old_vn, new_vn, strategy)
    end
  end

  def rollback_flow_version(%Flow{} = flow, target_version_number) do
    current_version = get_active_version(flow)
    target_version = get_version(flow.id, target_version_number)

    cond do
      is_nil(current_version) -> {:error, :no_active_version}
      is_nil(target_version) -> {:error, :version_not_found}
      true -> do_rollback(flow, current_version, target_version)
    end
  end

  def migration_status(flow_id) do
    FlowInstance
    |> where([i], i.flow_id == ^flow_id)
    |> where([i], i.status in ["running", "waiting"])
    |> group_by(:version_number)
    |> select([i], {i.version_number, count(i.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp validate_versions(nil, _old), do: {:error, :version_not_found}
  defp validate_versions(_new, nil), do: {:error, :no_active_version}

  defp validate_versions(%{id: id}, %{id: id}), do: {:error, :same_version}
  defp validate_versions(_new, _old), do: {:ok, :valid}

  defp do_version_transition(flow, old_version, new_version) do
    Repo.transaction(fn ->
      published = ensure_published(new_version)

      old_version |> FlowVersion.deprecate_changeset() |> safe_update!()
      flow |> Flow.active_version_changeset(published.id) |> safe_update!()

      {old_version.version_number, published.version_number}
    end)
  end

  defp ensure_published(%FlowVersion{status: "draft"} = version) do
    case publish_version(version) do
      {:ok, v} -> v
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_published(%FlowVersion{status: "published"} = version), do: version
  defp ensure_published(%FlowVersion{}), do: Repo.rollback(:version_not_publishable)

  defp do_rollback(flow, current_version, target_version) do
    Repo.transaction(fn ->
      # Mark current as rolled back
      current_version
      |> FlowVersion.rollback_changeset()
      |> safe_update!()

      # Republish target
      target_version
      |> FlowVersion.republish_changeset()
      |> safe_update!()

      # Update flow's active version
      flow
      |> Flow.active_version_changeset(target_version.id)
      |> safe_update!()

      {current_version.version_number, target_version.version_number}
    end)
    |> case do
      {:ok, {from_vn, to_vn}} ->
        Migrator.rollback(flow.id, from_vn, to_vn)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_active_version(%Flow{active_version_id: nil}), do: nil

  defp get_active_version(%Flow{active_version_id: id}) do
    Repo.get(FlowVersion, id)
  end

  # --- Private ---

  # Like Repo.update! but rolls back the transaction on invalid changeset
  # instead of raising Ecto.InvalidChangesetError (which bypasses fallback handling)
  defp safe_update!(%Ecto.Changeset{valid?: false} = cs) do
    Repo.rollback({:invalid_changeset, cs})
  end

  defp safe_update!(%Ecto.Changeset{} = cs), do: Repo.update!(cs)

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
