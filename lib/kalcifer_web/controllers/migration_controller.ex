defmodule KalciferWeb.MigrationController do
  use KalciferWeb, :controller

  alias Kalcifer.Flows

  action_fallback KalciferWeb.FallbackController

  @valid_strategies ~w(new_entries_only migrate_all)

  def migrate(conn, %{"flow_id" => flow_id, "version_number" => vn_str} = params) do
    strategy = Map.get(params, "strategy", "new_entries_only")

    with {:ok, _} <- validate_strategy(strategy),
         {:ok, flow} <- fetch_tenant_flow(conn, flow_id),
         {:ok, vn} <- parse_version_number(vn_str),
         {:ok, result} <- Flows.migrate_flow_version(flow, vn, strategy) do
      json(conn, %{data: serialize_result(result)})
    end
  end

  def rollback(conn, %{"flow_id" => flow_id, "version_number" => vn_str}) do
    with {:ok, flow} <- fetch_tenant_flow(conn, flow_id),
         {:ok, vn} <- parse_version_number(vn_str),
         {:ok, result} <- Flows.rollback_flow_version(flow, vn) do
      json(conn, %{data: serialize_result(result)})
    end
  end

  def status(conn, %{"flow_id" => flow_id}) do
    with {:ok, _flow} <- fetch_tenant_flow(conn, flow_id) do
      status = Flows.migration_status(flow_id)
      json(conn, %{data: status})
    end
  end

  defp fetch_tenant_flow(conn, flow_id) do
    tenant = conn.assigns.current_tenant

    case Flows.get_flow(flow_id) do
      %{tenant_id: tid} = flow when tid == tenant.id -> {:ok, flow}
      _ -> {:error, :not_found}
    end
  end

  defp validate_strategy(strategy) when strategy in @valid_strategies, do: {:ok, strategy}
  defp validate_strategy(_), do: {:error, :invalid_strategy}

  defp parse_version_number(str) do
    case Integer.parse(str) do
      {vn, ""} -> {:ok, vn}
      _ -> {:error, :invalid_version}
    end
  end

  defp serialize_result(result) do
    %{
      migrated: result.migrated,
      exited: result.exited,
      skipped: result.skipped,
      failed: Enum.map(result.failed, fn f -> %{id: f.id, reason: inspect(f.reason)} end)
    }
  end
end
