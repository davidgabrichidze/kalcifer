defmodule Kalcifer.Analytics do
  @moduledoc false

  import Ecto.Query

  alias Kalcifer.Analytics.Conversion
  alias Kalcifer.Analytics.FlowStats
  alias Kalcifer.Analytics.NodeStats
  alias Kalcifer.Repo

  # --- Flow Stats ---

  def upsert_flow_stats(flow_id, version_number, date, counts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      flow_id: flow_id,
      version_number: version_number,
      date: date,
      entered: Map.get(counts, :entered, 0),
      completed: Map.get(counts, :completed, 0),
      failed: Map.get(counts, :failed, 0),
      exited: Map.get(counts, :exited, 0),
      inserted_at: now,
      updated_at: now
    }

    Repo.insert(
      FlowStats.changeset(%FlowStats{}, attrs),
      on_conflict:
        from(s in FlowStats,
          update: [
            inc: [
              entered: ^attrs.entered,
              completed: ^attrs.completed,
              failed: ^attrs.failed,
              exited: ^attrs.exited
            ],
            set: [updated_at: ^now]
          ]
        ),
      conflict_target: [:flow_id, :version_number, :date]
    )
  end

  def upsert_node_stats(flow_id, version_number, node_id, date, counts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      flow_id: flow_id,
      version_number: version_number,
      node_id: node_id,
      date: date,
      executed: Map.get(counts, :executed, 0),
      completed: Map.get(counts, :completed, 0),
      failed: Map.get(counts, :failed, 0),
      branch_counts: Map.get(counts, :branch_counts, %{}),
      inserted_at: now,
      updated_at: now
    }

    Repo.insert(
      NodeStats.changeset(%NodeStats{}, attrs),
      on_conflict:
        from(s in NodeStats,
          update: [
            inc: [
              executed: ^attrs.executed,
              completed: ^attrs.completed,
              failed: ^attrs.failed
            ],
            set: [
              branch_counts:
                fragment(
                  "COALESCE(?.branch_counts, '{}'::jsonb) || ?::jsonb",
                  s,
                  ^attrs.branch_counts
                ),
              updated_at: ^now
            ]
          ]
        ),
      conflict_target: [:flow_id, :version_number, :node_id, :date]
    )
  end

  # --- Query functions ---

  def flow_summary(flow_id, date_range) do
    from(s in FlowStats,
      where: s.flow_id == ^flow_id,
      where: s.date >= ^date_range.first and s.date <= ^date_range.last,
      select: %{
        entered: sum(s.entered),
        completed: sum(s.completed),
        failed: sum(s.failed),
        exited: sum(s.exited)
      }
    )
    |> Repo.one()
    |> default_summary()
  end

  def node_breakdown(flow_id, version_number, date_range) do
    from(s in NodeStats,
      where: s.flow_id == ^flow_id,
      where: s.version_number == ^version_number,
      where: s.date >= ^date_range.first and s.date <= ^date_range.last,
      group_by: s.node_id,
      select: %{
        node_id: s.node_id,
        executed: sum(s.executed),
        completed: sum(s.completed),
        failed: sum(s.failed)
      }
    )
    |> Repo.all()
  end

  def ab_test_results(flow_id, node_id, date_range) do
    from(s in NodeStats,
      where: s.flow_id == ^flow_id,
      where: s.node_id == ^node_id,
      where: s.date >= ^date_range.first and s.date <= ^date_range.last,
      select: s.branch_counts
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn counts, acc ->
      Map.merge(acc, counts || %{}, fn _k, v1, v2 ->
        (v1 || 0) + (v2 || 0)
      end)
    end)
  end

  def funnel(flow_id, node_ids) when is_list(node_ids) do
    today = Date.utc_today()
    range = Date.range(Date.add(today, -30), today)

    stats =
      from(s in NodeStats,
        where: s.flow_id == ^flow_id,
        where: s.node_id in ^node_ids,
        where: s.date >= ^range.first and s.date <= ^range.last,
        group_by: s.node_id,
        select: {s.node_id, sum(s.executed)}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(node_ids, fn node_id ->
      %{node_id: node_id, count: Map.get(stats, node_id, 0)}
    end)
  end

  # --- Conversions ---

  def record_conversion(attrs) do
    %Conversion{}
    |> Conversion.changeset(attrs)
    |> Repo.insert()
  end

  def conversion_count(flow_id, date_range) do
    from(c in Conversion,
      where: c.flow_id == ^flow_id,
      where: c.converted_at >= ^date_range_to_datetime(date_range.first),
      where: c.converted_at <= ^date_range_to_datetime_end(date_range.last),
      select: count(c.id)
    )
    |> Repo.one()
  end

  defp date_range_to_datetime(date) do
    DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  end

  defp date_range_to_datetime_end(date) do
    DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
  end

  defp default_summary(nil), do: %{entered: 0, completed: 0, failed: 0, exited: 0}

  defp default_summary(summary) do
    %{
      entered: summary.entered || 0,
      completed: summary.completed || 0,
      failed: summary.failed || 0,
      exited: summary.exited || 0
    }
  end
end
