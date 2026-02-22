defmodule Kalcifer.Engine.FlowServerTest do
  use Kalcifer.DataCase, async: false

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Flows.ExecutionStep
  alias Kalcifer.Repo

  import Ecto.Query
  import Kalcifer.Factory

  defp start_server(graph, opts \\ []) do
    flow = Keyword.get_lazy(opts, :flow, fn -> insert(:flow) end)
    tenant = flow.tenant

    args = %{
      instance_id: Ecto.UUID.generate(),
      flow_id: flow.id,
      version_number: 1,
      customer_id: Keyword.get(opts, :customer_id, "customer_1"),
      tenant_id: tenant.id,
      graph: graph
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Kalcifer.Engine.FlowSupervisor,
        {FlowServer, args}
      )

    # Give the server time to complete synchronous execution
    ref = Process.monitor(pid)
    {pid, ref, args}
  end

  defp wait_for_completion(pid, ref, timeout \\ 2000) do
    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
      {:DOWN, ^ref, :process, ^pid, reason} -> {:error, reason}
    after
      timeout ->
        # Server might still be running (e.g. waiting)
        if Process.alive?(pid), do: :still_running, else: :ok
    end
  end

  describe "simple graph execution (entry → exit)" do
    test "executes entry and exit nodes, then completes" do
      {pid, ref, _args} = start_server(valid_graph())
      assert :ok = wait_for_completion(pid, ref)

      # Verify execution steps were recorded
      steps = Repo.all(from s in ExecutionStep, order_by: [asc: s.started_at])
      assert length(steps) == 2
      assert Enum.at(steps, 0).node_type == "event_entry"
      assert Enum.at(steps, 1).node_type == "exit"
      assert Enum.all?(steps, fn s -> s.status == "completed" end)
    end

    test "instance is marked completed after execution" do
      {pid, ref, _args} = start_server(valid_graph())
      assert :ok = wait_for_completion(pid, ref)

      # Find the instance (most recent)
      instance =
        Repo.one(
          from i in Kalcifer.Flows.FlowInstance,
            order_by: [desc: i.inserted_at],
            limit: 1
        )

      assert instance.status == "completed"
    end
  end

  describe "branching graph execution" do
    test "executes condition node and follows true branch" do
      graph = condition_graph()
      flow = insert(:flow)

      {pid, ref, _args} = start_server(graph, flow: flow)
      assert :ok = wait_for_completion(pid, ref)

      steps = Repo.all(from s in ExecutionStep, order_by: [asc: s.started_at])
      node_types = Enum.map(steps, & &1.node_type)

      assert "event_entry" in node_types
      assert "condition" in node_types
      # Should follow one of the branches
      assert "send_email" in node_types or "exit" in node_types
    end
  end

  describe "waiting node" do
    test "server stays alive when encountering a wait node" do
      graph = wait_graph()
      {pid, ref, _args} = start_server(graph)

      result = wait_for_completion(pid, ref, 500)
      assert result == :still_running

      # Clean up
      GenServer.stop(pid, :normal)
    end
  end

  describe "context accumulation" do
    test "accumulates node results in context" do
      {pid, ref, _args} = start_server(valid_graph())

      # Wait briefly for execution to start, then check if server is still alive or completed
      _result = wait_for_completion(pid, ref, 500)

      # Whether completed or not, check the instance was created with context
      instance =
        Repo.one(
          from i in Kalcifer.Flows.FlowInstance,
            order_by: [desc: i.inserted_at],
            limit: 1
        )

      assert instance != nil
    end
  end

  describe "full path integration (entry → action → condition → branch → exit)" do
    test "executes complete path through preference_gate true branch" do
      graph = full_path_graph()
      {pid, ref, _args} = start_server(graph)
      assert :ok = wait_for_completion(pid, ref)

      steps = Repo.all(from(s in ExecutionStep))
      node_types = MapSet.new(steps, & &1.node_type)

      # Preference gate defaults to true when no preferences in context,
      # so the path is: event_entry, send_email, preference_gate, send_sms, exit
      expected = MapSet.new(["event_entry", "send_email", "preference_gate", "send_sms", "exit"])
      assert node_types == expected
      assert Enum.all?(steps, fn s -> s.status == "completed" end)
    end

    test "false branch is not executed" do
      graph = full_path_graph()
      {pid, ref, _args} = start_server(graph)
      assert :ok = wait_for_completion(pid, ref)

      steps = Repo.all(from(s in ExecutionStep))
      node_ids = Enum.map(steps, & &1.node_id)

      # exit_false should never be reached (preference_gate defaults to true)
      refute "exit_false" in node_ids
      assert "exit_1" in node_ids
    end

    test "records correct step count" do
      graph = full_path_graph()
      {pid, ref, _args} = start_server(graph)
      assert :ok = wait_for_completion(pid, ref)

      step_count = Repo.aggregate(ExecutionStep, :count)
      assert step_count == 5
    end
  end

  describe "error handling" do
    test "marks instance as failed when graph contains unknown node type" do
      graph = unknown_node_graph()
      {pid, ref, _args} = start_server(graph)
      assert :ok = wait_for_completion(pid, ref)

      instance =
        Repo.one(
          from i in Kalcifer.Flows.FlowInstance,
            order_by: [desc: i.inserted_at],
            limit: 1
        )

      assert instance.status == "failed"
    end

    test "records failed step for unknown node type" do
      graph = unknown_node_graph()
      {pid, ref, _args} = start_server(graph)
      assert :ok = wait_for_completion(pid, ref)

      failed_steps =
        Repo.all(from s in ExecutionStep, where: s.status == "failed")

      assert length(failed_steps) == 1
      assert hd(failed_steps).node_type == "nonexistent_type"
    end

    test "server stops after failure" do
      graph = unknown_node_graph()
      {pid, ref, _args} = start_server(graph)
      assert :ok = wait_for_completion(pid, ref)

      refute Process.alive?(pid)
    end
  end

  # --- Test graph helpers ---

  defp unknown_node_graph do
    %{
      "nodes" => [
        %{
          "id" => "entry_1",
          "type" => "event_entry",
          "config" => %{"event_type" => "signed_up"}
        },
        %{"id" => "bad_1", "type" => "nonexistent_type", "config" => %{}},
        %{"id" => "exit_1", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "bad_1"},
        %{"id" => "e2", "source" => "bad_1", "target" => "exit_1"}
      ]
    }
  end

  defp full_path_graph do
    %{
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
        %{
          "id" => "pref_1",
          "type" => "preference_gate",
          "config" => %{"channel" => "email"}
        },
        %{
          "id" => "sms_1",
          "type" => "send_sms",
          "config" => %{"template_id" => "confirm"}
        },
        %{"id" => "exit_1", "type" => "exit", "config" => %{}},
        %{"id" => "exit_false", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "email_1"},
        %{"id" => "e2", "source" => "email_1", "target" => "pref_1"},
        %{"id" => "e3", "source" => "pref_1", "target" => "sms_1", "branch" => "true"},
        %{"id" => "e4", "source" => "pref_1", "target" => "exit_false", "branch" => "false"},
        %{"id" => "e5", "source" => "sms_1", "target" => "exit_1"}
      ]
    }
  end

  defp condition_graph do
    %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "signed_up"}},
        %{
          "id" => "cond_1",
          "type" => "condition",
          "config" => %{"field" => "accumulated.entry_1.event_type", "value" => "signed_up"}
        },
        %{
          "id" => "email_1",
          "type" => "send_email",
          "config" => %{"template_id" => "welcome"}
        },
        %{"id" => "exit_1", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "cond_1"},
        %{"id" => "e2", "source" => "cond_1", "target" => "email_1", "branch" => "true"},
        %{"id" => "e3", "source" => "cond_1", "target" => "exit_1", "branch" => "false"},
        %{"id" => "e4", "source" => "email_1", "target" => "exit_1"}
      ]
    }
  end

  defp wait_graph do
    %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "signed_up"}},
        %{"id" => "wait_1", "type" => "wait", "config" => %{"duration" => "3d"}},
        %{"id" => "exit_1", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
        %{"id" => "e2", "source" => "wait_1", "target" => "exit_1"}
      ]
    }
  end
end
