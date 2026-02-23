defmodule KalciferWeb.AnalyticsController do
  use KalciferWeb, :controller

  alias Kalcifer.Analytics

  action_fallback KalciferWeb.FallbackController

  def summary(conn, %{"flow_id" => flow_id} = params) do
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

  def nodes(conn, %{"flow_id" => flow_id} = params) do
    range = parse_date_range(params)
    version = parse_version(params)
    breakdown = Analytics.node_breakdown(flow_id, version, range)

    json(conn, %{data: breakdown})
  end

  def funnel(conn, %{"flow_id" => flow_id} = params) do
    node_ids = Map.get(params, "node_ids", [])
    stats = Analytics.funnel(flow_id, node_ids)

    json(conn, %{data: stats})
  end

  def ab_results(conn, %{"flow_id" => _flow_id, "node_id" => node_id} = params) do
    flow_id = params["flow_id"]
    range = parse_date_range(params)
    results = Analytics.ab_test_results(flow_id, node_id, range)

    json(conn, %{data: results})
  end

  defp parse_date_range(params) do
    today = Date.utc_today()

    from_date =
      case params["from"] do
        nil -> Date.add(today, -30)
        date_str -> Date.from_iso8601!(date_str)
      end

    to_date =
      case params["to"] do
        nil -> today
        date_str -> Date.from_iso8601!(date_str)
      end

    Date.range(from_date, to_date)
  end

  defp parse_version(%{"version" => v}) when is_binary(v), do: String.to_integer(v)
  defp parse_version(%{"version" => v}) when is_integer(v), do: v
  defp parse_version(_), do: 1
end
