defmodule Kalcifer.Engine.EventRouterTest do
  use Kalcifer.DataCase, async: false

  alias Kalcifer.Engine.EventRouter
  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Flows.ExecutionStep
  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Repo

  import Ecto.Query
  import Kalcifer.Factory

  defp start_server(graph, opts) do
    flow = Keyword.get_lazy(opts, :flow, fn -> insert(:flow) end)
    customer_id = Keyword.get(opts, :customer_id, "customer_1")

    args = %{
      instance_id: Ecto.UUID.generate(),
      flow_id: flow.id,
      version_number: 1,
      customer_id: customer_id,
      tenant_id: flow.tenant_id,
      graph: graph
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Kalcifer.Engine.FlowSupervisor,
        {FlowServer, args}
      )

    ref = Process.monitor(pid)
    {pid, ref, args}
  end

  defp wait_for_waiting(pid, timeout \\ 500) do
    Process.sleep(timeout)
    assert Process.alive?(pid)
    state = GenServer.call(pid, :get_state)
    assert state.status == :waiting
    state
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

  defp wait_for_event_graph do
    %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "signed_up"}},
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

  describe "route_event/3" do
    test "routes event to waiting FlowServer and follows event_received branch" do
      {pid, ref, _args} = start_server(wait_for_event_graph(), customer_id: "cust_1")
      wait_for_waiting(pid)

      result = EventRouter.route_event("cust_1", "email_opened", %{email_id: "abc"})
      assert [{:ok, _instance_id}] = result

      assert :ok = wait_for_completion(pid, ref)

      steps = Repo.all(from(s in ExecutionStep))
      node_ids = Enum.map(steps, & &1.node_id)

      # event_received branch: email_1, not sms_1
      assert "email_1" in node_ids
      refute "sms_1" in node_ids
    end

    test "ignores instances waiting for different event type" do
      {pid, _ref, _args} = start_server(wait_for_event_graph(), customer_id: "cust_2")
      wait_for_waiting(pid)

      result = EventRouter.route_event("cust_2", "purchase_completed")
      assert result == []

      state = GenServer.call(pid, :get_state)
      assert state.status == :waiting

      GenServer.stop(pid, :normal)
    end

    test "returns empty list for non-waiting instances" do
      {pid, ref, _args} = start_server(valid_graph(), customer_id: "cust_3")
      assert :ok = wait_for_completion(pid, ref)

      result = EventRouter.route_event("cust_3", "email_opened")
      assert result == []
    end

    test "returns not_alive when FlowServer is dead" do
      flow = insert(:flow)

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: flow.tenant,
          status: "waiting",
          customer_id: "cust_4",
          version_number: 1,
          current_nodes: ["wait_1"],
          context: %{
            "_waiting_node_id" => "wait_1",
            "_waiting_event_type" => "email_opened"
          }
        )

      instance_id = instance.id
      result = EventRouter.route_event("cust_4", "email_opened")
      assert [{:not_alive, ^instance_id}] = result
    end
  end

  describe "idempotent resume" do
    test "stale timeout is ignored after event resume" do
      {pid, ref, _args} = start_server(wait_for_event_graph(), customer_id: "cust_5")
      wait_for_waiting(pid)

      # Resume via event
      EventRouter.route_event("cust_5", "email_opened", %{email_id: "abc"})
      assert :ok = wait_for_completion(pid, ref)

      # Stale timeout cast to a dead process — no crash
      via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, "nonexistent"}}
      GenServer.cast(via, {:resume, "wait_1", :timeout})

      instance =
        Repo.one(
          from i in FlowInstance,
            order_by: [desc: i.inserted_at],
            limit: 1
        )

      assert instance.status == "completed"
    end
  end
end
