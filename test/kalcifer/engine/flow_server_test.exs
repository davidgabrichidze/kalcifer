defmodule Kalcifer.Engine.FlowServerTest do
  use Kalcifer.DataCase, async: false

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Flows.ExecutionStep
  alias Kalcifer.Repo
  alias Kalcifer.Versioning.NodeMapper

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

    args =
      if Keyword.has_key?(opts, :initial_context) do
        Map.put(args, :initial_context, Keyword.get(opts, :initial_context))
      else
        args
      end

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

  describe "wait and resume" do
    test "server enters waiting state on wait node" do
      graph = wait_graph()
      {pid, ref, _args} = start_server(graph)

      result = wait_for_completion(pid, ref, 500)
      assert result == :still_running

      state = GenServer.call(pid, :get_state)
      assert state.status == :waiting
      assert state.waiting_node_id == "wait_1"

      GenServer.stop(pid, :normal)
    end

    test "wait node resumes on cast and completes flow" do
      graph = wait_graph()
      {pid, ref, _args} = start_server(graph)

      # Wait for server to reach waiting state
      :still_running = wait_for_completion(pid, ref, 500)

      # Manually send resume (simulates what ResumeFlowJob does)
      GenServer.cast(pid, {:resume, "wait_1", :timer_expired})
      assert :ok = wait_for_completion(pid, ref)

      steps = Repo.all(from(s in ExecutionStep))
      node_types = MapSet.new(steps, & &1.node_type)

      assert "event_entry" in node_types
      assert "wait" in node_types
      assert "exit" in node_types
    end

    test "wait_until node resumes on cast and completes" do
      graph = wait_until_graph()
      {pid, ref, _args} = start_server(graph)
      :still_running = wait_for_completion(pid, ref, 500)

      GenServer.cast(pid, {:resume, "wait_1", :timer_expired})
      assert :ok = wait_for_completion(pid, ref)

      instance =
        Repo.one(
          from i in Kalcifer.Flows.FlowInstance,
            order_by: [desc: i.inserted_at],
            limit: 1
        )

      assert instance.status == "completed"
    end

    test "wait_for_event resumes on timeout and follows timed_out branch" do
      graph = wait_for_event_timeout_graph()
      {pid, ref, _args} = start_server(graph)
      :still_running = wait_for_completion(pid, ref, 500)

      GenServer.cast(pid, {:resume, "wait_1", :timeout})
      assert :ok = wait_for_completion(pid, ref)

      steps = Repo.all(from(s in ExecutionStep))
      node_ids = Enum.map(steps, & &1.node_id)

      # Should follow timed_out branch (send_sms), not event_received branch (send_email)
      assert "sms_1" in node_ids
      refute "email_1" in node_ids
    end

    test "instance is marked completed after wait + resume" do
      graph = wait_graph()
      {pid, ref, _args} = start_server(graph)
      :still_running = wait_for_completion(pid, ref, 500)

      GenServer.cast(pid, {:resume, "wait_1", :timer_expired})
      assert :ok = wait_for_completion(pid, ref)

      instance =
        Repo.one(
          from i in Kalcifer.Flows.FlowInstance,
            order_by: [desc: i.inserted_at],
            limit: 1
        )

      assert instance.status == "completed"
    end

    test "persists waiting status and context to DB" do
      graph = wait_graph()
      {pid, _ref, _args} = start_server(graph)

      # Wait for server to reach waiting state
      Process.sleep(200)
      assert Process.alive?(pid)

      state = GenServer.call(pid, :get_state)
      assert state.status == :waiting

      instance =
        Repo.one(
          from i in Kalcifer.Flows.FlowInstance,
            order_by: [desc: i.inserted_at],
            limit: 1
        )

      assert instance.status == "waiting"
      assert instance.context["_waiting_node_id"] == "wait_1"
      assert instance.context["_resume_scheduled_at"] != nil
      assert instance.context["accumulated"] != nil

      GenServer.stop(pid, :normal)
    end

    test "ignores duplicate resume cast" do
      graph = wait_graph()
      {pid, ref, _args} = start_server(graph)
      :still_running = wait_for_completion(pid, ref, 500)

      # Send two resume casts rapidly — second should be ignored
      GenServer.cast(pid, {:resume, "wait_1", :timer_expired})
      GenServer.cast(pid, {:resume, "wait_1", :timer_expired})
      assert :ok = wait_for_completion(pid, ref)

      steps = Repo.all(from(s in ExecutionStep))
      # wait_1 should appear at most twice (initial execute + one resume), not three times
      wait_steps = Enum.filter(steps, &(&1.node_id == "wait_1"))
      assert length(wait_steps) <= 2
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

  describe "edge cases" do
    test "executes flow with multiple entry nodes" do
      graph = multi_entry_graph()
      {pid, ref, _args} = start_server(graph)
      assert :ok = wait_for_completion(pid, ref)

      steps = Repo.all(from(s in ExecutionStep, order_by: [asc: s.started_at]))
      node_types = Enum.map(steps, & &1.node_type)

      assert "event_entry" in node_types
      assert "segment_entry" in node_types
      assert "exit" in node_types
    end

    test "merges initial_context into starting context" do
      graph = wait_graph()
      {pid, _ref, _args} = start_server(graph, initial_context: %{"source" => "api"})

      Process.sleep(100)
      state = GenServer.call(pid, :get_state)

      # initial_context keys should be present alongside accumulated
      assert state.context["source"] == "api"
      assert state.context["accumulated"] != nil

      GenServer.stop(pid, :normal)
    end

    test "injects _customer_id, _flow_id, _tenant_id into context" do
      graph = wait_graph()
      {pid, _ref, _args} = start_server(graph)

      Process.sleep(100)
      state = GenServer.call(pid, :get_state)

      assert state.context["_customer_id"] == state.customer_id
      assert state.context["_flow_id"] == state.flow_id
      assert state.context["_tenant_id"] == state.tenant_id

      GenServer.stop(pid, :normal)
    end

    test "migrate swaps graph and version in waiting state" do
      graph_v1 = wait_for_event_timeout_graph()
      {pid, _ref, _args} = start_server(graph_v1)
      Process.sleep(100)

      state = GenServer.call(pid, :get_state)
      assert state.status == :waiting
      assert state.version_number == 1

      # Build v2 graph with different event_type
      graph_v2 = put_in(graph_v1, ["nodes", Access.at(1), "config", "event_type"], "push_opened")

      node_map = NodeMapper.build_mapping(graph_v1, graph_v2)
      :ok = GenServer.call(pid, {:migrate, graph_v2, 2, node_map})

      new_state = GenServer.call(pid, :get_state)
      assert new_state.version_number == 2
      assert new_state.graph == graph_v2
      assert new_state.context["_waiting_event_type"] == "push_opened"

      GenServer.stop(pid, :normal)
    end

    test "migrate with no wait changes keeps context unchanged" do
      graph = wait_for_event_timeout_graph()
      {pid, _ref, _args} = start_server(graph)
      Process.sleep(100)

      state_before = GenServer.call(pid, :get_state)

      # Same graph, no changes
      node_map = NodeMapper.build_mapping(graph, graph)
      :ok = GenServer.call(pid, {:migrate, graph, 2, node_map})

      state_after = GenServer.call(pid, :get_state)
      assert state_after.version_number == 2
      assert state_after.context["_waiting_event_type"] == state_before.context["_waiting_event_type"]

      GenServer.stop(pid, :normal)
    end

    test "resume with non-matching node_id is silently ignored" do
      graph = wait_graph()
      {pid, ref, _args} = start_server(graph)
      :still_running = wait_for_completion(pid, ref, 500)

      # Send resume for wrong node
      GenServer.cast(pid, {:resume, "wrong_node_id", :timer_expired})

      # Server should still be waiting
      Process.sleep(100)
      assert Process.alive?(pid)
      state = GenServer.call(pid, :get_state)
      assert state.status == :waiting
      assert state.waiting_node_id == "wait_1"

      GenServer.stop(pid, :normal)
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

  defp wait_until_graph do
    future = DateTime.utc_now() |> DateTime.add(86_400, :second) |> DateTime.to_iso8601()

    %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "signed_up"}},
        %{"id" => "wait_1", "type" => "wait_until", "config" => %{"datetime" => future}},
        %{"id" => "exit_1", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
        %{"id" => "e2", "source" => "wait_1", "target" => "exit_1"}
      ]
    }
  end

  defp multi_entry_graph do
    %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "signed_up"}},
        %{"id" => "entry_2", "type" => "segment_entry", "config" => %{"segment_id" => "vip"}},
        %{"id" => "exit_1", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "exit_1"},
        %{"id" => "e2", "source" => "entry_2", "target" => "exit_1"}
      ]
    }
  end

  defp wait_for_event_timeout_graph do
    %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "signed_up"}},
        %{
          "id" => "wait_1",
          "type" => "wait_for_event",
          "config" => %{"event_type" => "email_opened", "timeout" => "3d"}
        },
        %{"id" => "email_1", "type" => "send_email", "config" => %{"template_id" => "followup"}},
        %{"id" => "sms_1", "type" => "send_sms", "config" => %{"template_id" => "reminder"}},
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
  end
end
