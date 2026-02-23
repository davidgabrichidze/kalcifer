defmodule Kalcifer.Engine.CustomerEnrichmentTest do
  use Kalcifer.DataCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Customers
  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Engine.FlowTrigger
  alias Kalcifer.Flows

  describe "customer context enrichment on trigger" do
    test "enriches context with _customer when customer exists" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, graph: wait_graph())
      {:ok, flow} = Flows.activate_flow(flow)

      customer =
        insert(:customer,
          tenant: tenant,
          external_id: "enrich_test",
          email: "alice@example.com",
          name: "Alice",
          preferences: %{"email" => true, "sms" => false}
        )

      {:ok, instance_id} = FlowTrigger.trigger(flow.id, customer.external_id)

      # Wait for server to reach the wait node
      Process.sleep(100)

      state = FlowServer.get_state(instance_id)
      assert state.context["_customer"]["id"] == customer.id
      assert state.context["_customer"]["email"] == "alice@example.com"
      assert state.context["_customer"]["name"] == "Alice"
      assert state.context["_customer"]["preferences"] == %{"email" => true, "sms" => false}
    end

    test "preferences from customer are available at top level" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, graph: wait_graph())
      {:ok, flow} = Flows.activate_flow(flow)

      insert(:customer,
        tenant: tenant,
        external_id: "pref_test",
        preferences: %{"email" => true, "push" => false}
      )

      {:ok, instance_id} = FlowTrigger.trigger(flow.id, "pref_test")
      Process.sleep(100)

      state = FlowServer.get_state(instance_id)
      assert state.context["preferences"] == %{"email" => true, "push" => false}
    end

    test "trigger works without existing customer" do
      flow = insert(:flow)
      insert(:flow_version, flow: flow, graph: valid_graph())
      {:ok, flow} = Flows.activate_flow(flow)

      {:ok, instance_id} = FlowTrigger.trigger(flow.id, "unknown_customer")
      Process.sleep(100)

      instance = Kalcifer.Repo.get(Kalcifer.Flows.FlowInstance, instance_id)
      assert instance.customer_id == "unknown_customer"
    end

    test "initial_context is not overwritten by customer preferences" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, graph: wait_graph())
      {:ok, flow} = Flows.activate_flow(flow)

      insert(:customer,
        tenant: tenant,
        external_id: "ctx_test",
        preferences: %{"email" => true}
      )

      {:ok, instance_id} =
        FlowTrigger.trigger(flow.id, "ctx_test", %{"preferences" => %{"sms" => true}})

      Process.sleep(100)

      state = FlowServer.get_state(instance_id)
      # Map.put_new preserves the user-supplied preferences
      assert state.context["preferences"] == %{"sms" => true}
    end
  end

  describe "data action nodes with real customer" do
    test "update_profile updates customer fields in DB" do
      customer = insert(:customer, name: "Old Name")
      ctx = %{"_customer" => %{"id" => customer.id}}

      alias Kalcifer.Engine.Nodes.Action.Data.UpdateProfile

      assert {:completed, %{updated: true}} =
               UpdateProfile.execute(%{"fields" => %{name: "New Name"}}, ctx)

      reloaded = Customers.get_customer(customer.id)
      assert reloaded.name == "New Name"
    end

    test "add_tag persists tag to customer in DB" do
      customer = insert(:customer, tags: ["existing"])
      ctx = %{"_customer" => %{"id" => customer.id}}

      alias Kalcifer.Engine.Nodes.Action.Data.AddTag

      assert {:completed, %{tagged: true, tag: "vip"}} =
               AddTag.execute(%{"tag" => "vip"}, ctx)

      reloaded = Customers.get_customer(customer.id)
      assert "vip" in reloaded.tags
      assert "existing" in reloaded.tags
    end
  end

  # A graph that pauses at a wait node so we can inspect state
  defp wait_graph do
    %{
      "nodes" => [
        %{
          "id" => "entry_1",
          "type" => "event_entry",
          "config" => %{"event_type" => "signed_up"}
        },
        %{
          "id" => "wait_1",
          "type" => "wait_for_event",
          "config" => %{"event_type" => "some_event", "timeout" => "1d"}
        },
        %{
          "id" => "exit_1",
          "type" => "exit",
          "config" => %{}
        }
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
        %{"id" => "e2", "source" => "wait_1", "target" => "exit_1", "branch" => "event_received"},
        %{"id" => "e3", "source" => "wait_1", "target" => "exit_1", "branch" => "timed_out"}
      ]
    }
  end
end
