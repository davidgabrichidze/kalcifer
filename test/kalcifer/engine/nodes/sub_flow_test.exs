defmodule Kalcifer.Engine.Nodes.Action.SubFlowTest do
  # async: false — real execution spawns FlowServers needing shared sandbox
  use Kalcifer.DataCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Engine.Nodes.Action.SubFlow
  alias Kalcifer.Engine.Persistence.InstanceStore

  describe "execute/2 — dry run" do
    test "returns sub-flow metadata" do
      config = %{
        "flow_id" => Ecto.UUID.generate(),
        "context_mapping" => %{"user_name" => "name"}
      }

      context = %{"_dry_run" => true, "user_name" => "David"}

      assert {:completed, %{dry_run: true, sub_flow: sub}} =
               SubFlow.execute(config, context)

      assert sub.flow_id == config["flow_id"]
      assert sub.would_execute == true
    end
  end

  describe "validate/1" do
    test "accepts valid config" do
      assert :ok = SubFlow.validate(%{"flow_id" => Ecto.UUID.generate()})
    end

    test "rejects missing flow_id" do
      assert {:error, ["flow_id is required"]} = SubFlow.validate(%{})
    end

    test "rejects empty flow_id" do
      assert {:error, ["flow_id is required"]} = SubFlow.validate(%{"flow_id" => ""})
    end
  end

  describe "config_schema/0" do
    test "defines flow_id, context_mapping, wait, timeout" do
      schema = SubFlow.config_schema()
      assert Map.has_key?(schema, "flow_id")
      assert Map.has_key?(schema, "context_mapping")
      assert Map.has_key?(schema, "wait")
      assert Map.has_key?(schema, "timeout_ms")
    end
  end

  describe "category/0" do
    test "returns :action" do
      assert SubFlow.category() == :action
    end
  end

  describe "execute/2 — real execution" do
    defp activated_child_flow(tenant) do
      flow = insert(:flow, tenant: tenant, status: "active")

      version =
        insert(:flow_version,
          flow: flow,
          version_number: 1,
          status: "published",
          graph: %{
            "nodes" => [
              %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "go"}},
              %{"id" => "exit_1", "type" => "exit", "config" => %{}}
            ],
            "edges" => [%{"source" => "entry_1", "target" => "exit_1"}]
          }
        )

      flow
      |> Ecto.Changeset.change(active_version_id: version.id)
      |> Repo.update!()
    end

    test "async sub-flow starts a child instance and completes it" do
      tenant = insert(:tenant)
      child = activated_child_flow(tenant)

      context = %{"_customer_id" => "sub-cust-1", "_tenant_id" => tenant.id}

      assert {:completed, %{sub_flow: true, async: true, instance_id: instance_id}} =
               SubFlow.execute(%{"flow_id" => child.id}, context)

      # Child FlowServer runs async — wait for it to finish
      instance =
        wait_until(fn ->
          case InstanceStore.get_instance(instance_id) do
            %{status: "completed"} = found -> found
            _ -> nil
          end
        end)

      assert instance, "child instance did not complete"
      assert instance.flow_id == child.id
    end

    test "wait: true returns the child flow result" do
      tenant = insert(:tenant)
      child = activated_child_flow(tenant)

      context = %{"_customer_id" => "sub-cust-2", "_tenant_id" => tenant.id}

      assert {:completed, %{sub_flow: true, status: "completed", instance_id: _id}} =
               SubFlow.execute(
                 %{"flow_id" => child.id, "wait" => true, "timeout_ms" => 5_000},
                 context
               )
    end

    test "refuses to execute another tenant's flow" do
      other_tenant_flow = activated_child_flow(insert(:tenant))
      my_tenant = insert(:tenant)

      context = %{"_customer_id" => "sub-cust-3", "_tenant_id" => my_tenant.id}

      assert {:failed, %{reason: reason}} =
               SubFlow.execute(%{"flow_id" => other_tenant_flow.id}, context)

      assert reason =~ "not found"
    end

    defp wait_until(fun, attempts \\ 50) do
      case fun.() do
        nil when attempts > 0 ->
          Process.sleep(50)
          wait_until(fun, attempts - 1)

        result ->
          result
      end
    end
  end
end
