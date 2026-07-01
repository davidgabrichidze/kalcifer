defmodule Kalcifer.Analytics do
  @moduledoc false

  import Ecto.Query

  alias Kalcifer.Analytics.Conversion
  alias Kalcifer.Analytics.FlowStats
  alias Kalcifer.Analytics.NodeStats
  alias Kalcifer.Flows.ExecutionStep
  alias Kalcifer.Flows.FlowInstance
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

  @doc """
  Computes average execution duration per node from execution_steps.
  Returns a map of %{node_id => avg_duration_ms}.
  """
  def node_avg_durations(flow_id) do
    from(s in ExecutionStep,
      join: i in FlowInstance,
      on: s.instance_id == i.id,
      where: i.flow_id == ^flow_id,
      where: s.status == "completed",
      where: not is_nil(s.started_at),
      where: not is_nil(s.completed_at),
      group_by: s.node_id,
      select: {
        s.node_id,
        fragment(
          "ROUND(AVG(EXTRACT(EPOCH FROM (? - ?)) * 1000))",
          s.completed_at,
          s.started_at
        )
      }
    )
    |> Repo.all()
    |> Map.new()
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

  ## Daily rollup — recompute a date's stats from the source of truth

  @doc """
  Recomputes flow and node stats for a date from flow_instances and
  execution_steps, overwriting the counters (branch_counts are kept from
  live collection — branch keys are not persisted on steps). Dry-run
  instances are excluded. Failed instances are attributed to the date
  they were last updated, as instances carry no failed_at timestamp.
  """
  def recompute_date(date) do
    flow_counts =
      %{}
      |> merge_flow_counts(instances_entered_on(date), :entered)
      |> merge_flow_counts(instances_completed_on(date), :completed)
      |> merge_flow_counts(instances_failed_on(date), :failed)
      |> merge_flow_counts(instances_exited_on(date), :exited)

    Enum.each(flow_counts, fn {{flow_id, version_number}, counts} ->
      set_flow_stats(flow_id, version_number, date, counts)
    end)

    date
    |> node_step_counts()
    |> Enum.each(fn {{flow_id, version_number, node_id}, counts} ->
      set_node_stats(flow_id, version_number, node_id, date, counts)
    end)

    :ok
  end

  def set_flow_stats(flow_id, version_number, date, counts) do
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
      on_conflict: [
        set: [
          entered: attrs.entered,
          completed: attrs.completed,
          failed: attrs.failed,
          exited: attrs.exited,
          updated_at: now
        ]
      ],
      conflict_target: [:flow_id, :version_number, :date]
    )
  end

  def set_node_stats(flow_id, version_number, node_id, date, counts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      flow_id: flow_id,
      version_number: version_number,
      node_id: node_id,
      date: date,
      executed: Map.get(counts, :executed, 0),
      completed: Map.get(counts, :completed, 0),
      failed: Map.get(counts, :failed, 0),
      branch_counts: %{},
      inserted_at: now,
      updated_at: now
    }

    Repo.insert(
      NodeStats.changeset(%NodeStats{}, attrs),
      on_conflict: [
        set: [
          executed: attrs.executed,
          completed: attrs.completed,
          failed: attrs.failed,
          updated_at: now
        ]
      ],
      conflict_target: [:flow_id, :version_number, :node_id, :date]
    )
  end

  defp merge_flow_counts(acc, rows, key) do
    Enum.reduce(rows, acc, fn {flow_key, count}, acc ->
      Map.update(acc, flow_key, %{key => count}, &Map.put(&1, key, count))
    end)
  end

  defp instances_entered_on(date) do
    from(i in FlowInstance,
      where: not i.dry_run and fragment("?::date", i.entered_at) == ^date,
      group_by: [i.flow_id, i.version_number],
      select: {{i.flow_id, i.version_number}, count(i.id)}
    )
    |> Repo.all()
  end

  defp instances_completed_on(date) do
    from(i in FlowInstance,
      where: not i.dry_run and fragment("?::date", i.completed_at) == ^date,
      group_by: [i.flow_id, i.version_number],
      select: {{i.flow_id, i.version_number}, count(i.id)}
    )
    |> Repo.all()
  end

  defp instances_failed_on(date) do
    from(i in FlowInstance,
      where:
        not i.dry_run and i.status == "failed" and
          fragment("?::date", i.updated_at) == ^date,
      group_by: [i.flow_id, i.version_number],
      select: {{i.flow_id, i.version_number}, count(i.id)}
    )
    |> Repo.all()
  end

  defp instances_exited_on(date) do
    from(i in FlowInstance,
      where: not i.dry_run and fragment("?::date", i.exited_at) == ^date,
      group_by: [i.flow_id, i.version_number],
      select: {{i.flow_id, i.version_number}, count(i.id)}
    )
    |> Repo.all()
  end

  defp node_step_counts(date) do
    from(s in ExecutionStep,
      join: i in assoc(s, :instance),
      where: not i.dry_run and fragment("?::date", s.started_at) == ^date,
      group_by: [i.flow_id, s.version_number, s.node_id, s.status],
      select: {{i.flow_id, s.version_number, s.node_id}, s.status, count(s.id)}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {node_key, status, count}, acc ->
      Map.update(
        acc,
        node_key,
        step_counts(status, count),
        &merge_step_counts(&1, status, count)
      )
    end)
  end

  defp step_counts(status, count) do
    merge_step_counts(%{executed: 0, completed: 0, failed: 0}, status, count)
  end

  defp merge_step_counts(counts, status, count) do
    counts = Map.update!(counts, :executed, &(&1 + count))

    case status do
      "completed" -> Map.update!(counts, :completed, &(&1 + count))
      "failed" -> Map.update!(counts, :failed, &(&1 + count))
      _ -> counts
    end
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
