defmodule Kalcifer.Engine.FlowServerDryRunTest do
  use Kalcifer.DataCase, async: false

  alias Kalcifer.Channels.Delivery
  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Flows.ExecutionStep
  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Repo

  import Ecto.Query
  import Kalcifer.Factory

  defp start_dry_run_server(graph, opts \\ []) do
    flow = Keyword.get_lazy(opts, :flow, fn -> insert(:flow) end)
    tenant = flow.tenant

    args = %{
      instance_id: Ecto.UUID.generate(),
      flow_id: flow.id,
      version_number: 1,
      customer_id: Keyword.get(opts, :customer_id, "customer_1"),
      tenant_id: tenant.id,
      graph: graph,
      dry_run: true,
      initial_context: Keyword.get(opts, :initial_context, %{})
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Kalcifer.Engine.FlowSupervisor,
        {FlowServer, args}
      )

    ref = Process.monitor(pid)
    {pid, ref, args}
  end

  defp wait_for_completion(pid, ref, timeout \\ 2000) do
    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
      {:DOWN, ^ref, :process, ^pid, reason} -> {:error, reason}
    after
      timeout ->
        if Process.alive?(pid), do: :still_running, else: :ok
    end
  end

  describe "dry_run flow with wait node completes instantly" do
    test "wait node is auto-skipped in dry_run mode" do
      graph = %{
        "nodes" => [
          %{
            "id" => "entry_1",
            "type" => "event_entry",
            "config" => %{"event_type" => "signed_up"}
          },
          %{"id" => "wait_1", "type" => "wait", "config" => %{"duration" => "3d"}},
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
          %{"id" => "e2", "source" => "wait_1", "target" => "exit_1"}
        ]
      }

      {pid, ref, args} = start_dry_run_server(graph)
      assert :ok = wait_for_completion(pid, ref)

      # Flow completed without needing manual resume
      instance = Repo.get(FlowInstance, args.instance_id)
      assert instance.status == "completed"
      assert instance.dry_run == true

      # All steps executed
      steps =
        Repo.all(
          from s in ExecutionStep,
            where: s.instance_id == ^args.instance_id,
            order_by: [asc: s.started_at]
        )

      node_types = Enum.map(steps, & &1.node_type)
      assert "event_entry" in node_types
      assert "wait" in node_types
      assert "exit" in node_types

      # Wait step output should indicate dry_run skip
      wait_step = Enum.find(steps, &(&1.node_type == "wait"))
      assert wait_step.output["dry_run"] == true
      assert wait_step.output["skipped_wait"] == "3d"
    end
  end

  describe "dry_run flow with action nodes skips side effects" do
    test "send_email node returns would_send in dry_run" do
      graph = %{
        "nodes" => [
          %{
            "id" => "entry_1",
            "type" => "event_entry",
            "config" => %{"event_type" => "signed_up"}
          },
          %{
            "id" => "email_1",
            "type" => "send_email",
            "config" => %{"template_id" => "welcome"}
          },
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "email_1"},
          %{"id" => "e2", "source" => "email_1", "target" => "exit_1"}
        ]
      }

      {pid, ref, args} = start_dry_run_server(graph)
      assert :ok = wait_for_completion(pid, ref)

      instance = Repo.get(FlowInstance, args.instance_id)
      assert instance.status == "completed"

      # Check email step output
      email_step =
        Repo.one(
          from s in ExecutionStep,
            where: s.instance_id == ^args.instance_id and s.node_type == "send_email"
        )

      assert email_step.output["dry_run"] == true
      assert email_step.output["would_send"]["channel"] == "email"
      assert email_step.output["would_send"]["template_id"] == "welcome"

      # No deliveries should have been created
      delivery_count =
        Repo.one(from d in Delivery, select: count(), where: d.instance_id == ^args.instance_id)

      assert delivery_count == 0
    end
  end

  describe "dry_run flow with condition branches correctly" do
    test "condition evaluates normally and follows correct branch" do
      graph = %{
        "nodes" => [
          %{
            "id" => "entry_1",
            "type" => "event_entry",
            "config" => %{"event_type" => "signed_up"}
          },
          %{
            "id" => "cond_1",
            "type" => "condition",
            "config" => %{"field" => "is_premium", "value" => true}
          },
          %{
            "id" => "email_1",
            "type" => "send_email",
            "config" => %{"template_id" => "premium_welcome"}
          },
          %{"id" => "exit_true", "type" => "exit", "config" => %{}},
          %{"id" => "exit_false", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "cond_1"},
          %{"id" => "e2", "source" => "cond_1", "target" => "email_1", "branch" => "true"},
          %{"id" => "e3", "source" => "cond_1", "target" => "exit_false", "branch" => "false"},
          %{"id" => "e4", "source" => "email_1", "target" => "exit_true"}
        ]
      }

      {pid, ref, args} =
        start_dry_run_server(graph, initial_context: %{"is_premium" => true})

      assert :ok = wait_for_completion(pid, ref)

      steps =
        Repo.all(
          from s in ExecutionStep,
            where: s.instance_id == ^args.instance_id,
            order_by: [asc: s.started_at]
        )

      node_types = Enum.map(steps, & &1.node_type)

      # Condition evaluated and took the true branch
      assert "condition" in node_types
      assert "send_email" in node_types

      # Email was dry-run, not actually sent
      email_step = Enum.find(steps, &(&1.node_type == "send_email"))
      assert email_step.output["dry_run"] == true
    end
  end

  describe "dry_run flow with wait_for_event auto-branches" do
    test "wait_for_event takes event_received branch in dry_run" do
      graph = %{
        "nodes" => [
          %{
            "id" => "entry_1",
            "type" => "event_entry",
            "config" => %{"event_type" => "signed_up"}
          },
          %{
            "id" => "wait_1",
            "type" => "wait_for_event",
            "config" => %{"event_type" => "email_opened", "timeout" => "3d"}
          },
          %{
            "id" => "email_1",
            "type" => "send_email",
            "config" => %{"template_id" => "followup"}
          },
          %{
            "id" => "sms_1",
            "type" => "send_sms",
            "config" => %{"template_id" => "reminder"}
          },
          %{"id" => "exit_1", "type" => "exit", "config" => %{}}
        ],
        "edges" => [
          %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
          %{
            "id" => "e2",
            "source" => "wait_1",
            "target" => "email_1",
            "branch" => "event_received"
          },
          %{"id" => "e3", "source" => "wait_1", "target" => "sms_1", "branch" => "timed_out"},
          %{"id" => "e4", "source" => "email_1", "target" => "exit_1"},
          %{"id" => "e5", "source" => "sms_1", "target" => "exit_1"}
        ]
      }

      {pid, ref, args} = start_dry_run_server(graph)
      assert :ok = wait_for_completion(pid, ref)

      steps =
        Repo.all(
          from s in ExecutionStep,
            where: s.instance_id == ^args.instance_id,
            order_by: [asc: s.started_at]
        )

      node_types = Enum.map(steps, & &1.node_type)

      # Should have followed event_received branch → send_email
      assert "wait_for_event" in node_types
      assert "send_email" in node_types
      # Should NOT have followed timed_out branch
      refute "send_sms" in node_types
    end
  end
end
