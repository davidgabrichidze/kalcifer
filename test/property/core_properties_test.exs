defmodule Kalcifer.Property.CorePropertiesTest do
  @moduledoc "Property-based tests for core engine invariants (P-001 through P-013)"

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Kalcifer.Engine.Duration
  alias Kalcifer.Engine.Nodes.Condition.Condition
  alias Kalcifer.Flows.FlowGraph

  # ── Generators ──────────────────────────────────────────────

  @node_types ~w(send_email send_sms send_push call_webhook)

  defp linear_dag_gen do
    gen all(
          middle_count <- integer(0..5),
          middle_types <- list_of(member_of(@node_types), length: middle_count)
        ) do
      entry = %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "x"}}
      exit_n = %{"id" => "exit_1", "type" => "exit", "config" => %{}}

      middles =
        middle_types
        |> Enum.with_index(1)
        |> Enum.map(fn {type, i} ->
          %{"id" => "mid_#{i}", "type" => type, "config" => %{}}
        end)

      all_nodes = [entry | middles] ++ [exit_n]
      node_ids = Enum.map(all_nodes, & &1["id"])

      edges =
        node_ids
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.with_index(1)
        |> Enum.map(fn {[src, tgt], i} ->
          %{"id" => "e#{i}", "source" => src, "target" => tgt}
        end)

      %{"nodes" => all_nodes, "edges" => edges}
    end
  end

  defp duration_gen do
    gen all(
          amount <- integer(0..999),
          unit <- member_of(~w(s m h d w))
        ) do
      "#{amount}#{unit}"
    end
  end

  # ── P-001: Valid DAG always passes validation ───────────────

  describe "P-001: valid DAG always passes validation" do
    property "randomly generated linear DAGs pass FlowGraph.validate/1" do
      check all(graph <- linear_dag_gen()) do
        assert :ok = FlowGraph.validate(graph)
      end
    end
  end

  # P-010: A/B split determinism — SKIPPED: current AbSplit uses :rand.uniform(),
  # not customer_id-based hashing. Determinism requires implementation change.

  # ── P-012: Condition node symmetry ──────────────────────────

  describe "P-012: condition equals/not_equals produce opposite branches" do
    property "equals and not_equals always return opposite branches for same input" do
      check all(
              field_val <- string(:alphanumeric, min_length: 1, max_length: 20),
              context_val <- string(:alphanumeric, min_length: 1, max_length: 20)
            ) do
        config_eq = %{"field" => "x", "operator" => "equals", "value" => field_val}
        config_neq = %{"field" => "x", "operator" => "not_equals", "value" => field_val}
        context = %{"x" => context_val}

        {:branched, branch_eq, _} = Condition.execute(config_eq, context)
        {:branched, branch_neq, _} = Condition.execute(config_neq, context)

        assert branch_eq != branch_neq
      end
    end
  end

  # ── P-013: Duration parse is always valid ───────────────────

  describe "P-013: duration parse always succeeds for valid format" do
    property "NNu format always parses to non-negative integer" do
      check all(duration <- duration_gen()) do
        assert {:ok, seconds} = Duration.to_seconds(duration)
        assert is_integer(seconds)
        assert seconds >= 0
      end
    end
  end
end
