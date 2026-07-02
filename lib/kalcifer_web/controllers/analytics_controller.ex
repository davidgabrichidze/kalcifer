defmodule KalciferWeb.AnalyticsController do
  use KalciferWeb, :controller

  alias Kalcifer.Analytics
  alias Kalcifer.Flows

  action_fallback KalciferWeb.FallbackController

  def summary(conn, %{"flow_id" => flow_id} = params) do
    with :ok <- authorize_flow(conn, flow_id) do
      range = parse_date_range(params)
      stats = Analytics.flow_summary(flow_id, range)
      conversions = Analytics.conversion_count(flow_id, range)

      json(conn, %{
        data:
          Map.merge(stats, %{
            conversions: conversions,
            date_range: %{from: range.first, to: range.last}
          })
      })
    end
  end

  def nodes(conn, %{"flow_id" => flow_id} = params) do
    with :ok <- authorize_flow(conn, flow_id) do
      range = parse_date_range(params)
      version = parse_version(params)
      breakdown = Analytics.node_breakdown(flow_id, version, range)
      durations = Analytics.node_avg_durations(flow_id)

      enriched =
        Enum.map(breakdown, fn node ->
          Map.put(node, :avg_duration_ms, Map.get(durations, node.node_id))
        end)

      json(conn, %{data: enriched})
    end
  end

  def funnel(conn, %{"flow_id" => flow_id} = params) do
    with :ok <- authorize_flow(conn, flow_id) do
      node_ids = Map.get(params, "node_ids", [])
      stats = Analytics.funnel(flow_id, node_ids)
      json(conn, %{data: stats})
    end
  end

  def ab_results(conn, %{"flow_id" => flow_id, "node_id" => node_id} = params) do
    with :ok <- authorize_flow(conn, flow_id) do
      range = parse_date_range(params)
      results = Analytics.ab_test_results(flow_id, node_id, range)
      json(conn, %{data: results})
    end
  end

  # Analytics is aggregate data — return not_found for another tenant's flow.
  defp authorize_flow(conn, flow_id) do
    tenant = KalciferWeb.TenantResolver.resolve(conn)

    case Flows.get_flow(flow_id) do
      %{tenant_id: tid} when tid == tenant.id -> :ok
      _ -> {:error, :not_found}
    end
  end

  defp parse_date_range(params) do
    today = Date.utc_today()
    from_date = parse_date(params["from"]) || Date.add(today, -30)
    to_date = parse_date(params["to"]) || today
    Date.range(from_date, to_date)
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_version(%{"version" => v}) when is_integer(v), do: v

  defp parse_version(%{"version" => v}) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> 1
    end
  end

  defp parse_version(_), do: 1
end
