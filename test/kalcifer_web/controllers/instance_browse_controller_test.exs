defmodule KalciferWeb.InstanceBrowseControllerTest do
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Flows
  alias Kalcifer.Engine.Persistence.{InstanceStore, StepStore}

  setup %{conn: conn} do
    tenant = insert(:tenant)
    flow = insert(:flow, tenant: tenant)
    version = insert(:flow_version, flow: flow, graph: valid_graph())
    {:ok, _flow} = Flows.activate_flow(flow)

    conn = put_req_header(conn, "content-type", "application/json")
    {:ok, conn: conn, tenant: tenant, flow: Flows.get_flow(flow.id), version: version}
  end

  describe "GET /api/v1/flows/:flow_id/instances" do
    test "returns empty list when no instances", %{conn: conn, flow: flow} do
      conn = get(conn, "/api/v1/flows/#{flow.id}/instances")
      assert %{"data" => []} = json_response(conn, 200)
    end

    test "returns instances for flow", %{conn: conn, flow: flow, tenant: tenant} do
      {:ok, instance} =
        InstanceStore.create_instance(%{
          flow_id: flow.id,
          version_number: 1,
          customer_id: "test_customer",
          tenant_id: tenant.id
        })

      conn = get(conn, "/api/v1/flows/#{flow.id}/instances")
      body = json_response(conn, 200)
      assert length(body["data"]) >= 1

      inst = Enum.find(body["data"], &(&1["id"] == instance.id))
      assert inst
      assert inst["customer_id"] == "test_customer"
      assert inst["status"] == "running"
    end

    test "filters by status", %{conn: conn, flow: flow, tenant: tenant} do
      {:ok, _running} =
        InstanceStore.create_instance(%{
          flow_id: flow.id,
          version_number: 1,
          customer_id: "cust_1",
          tenant_id: tenant.id
        })

      {:ok, completed} =
        InstanceStore.create_instance(%{
          flow_id: flow.id,
          version_number: 1,
          customer_id: "cust_2",
          tenant_id: tenant.id
        })

      InstanceStore.complete_instance(completed)

      conn = get(conn, "/api/v1/flows/#{flow.id}/instances?status=completed")
      body = json_response(conn, 200)
      assert Enum.all?(body["data"], &(&1["status"] == "completed"))
    end
  end

  describe "GET /api/v1/instances/:id" do
    test "returns instance with steps", %{conn: conn, flow: flow, tenant: tenant} do
      {:ok, instance} =
        InstanceStore.create_instance(%{
          flow_id: flow.id,
          version_number: 1,
          customer_id: "test_customer",
          tenant_id: tenant.id
        })

      node = %{"id" => "entry_1", "type" => "event_entry", "config" => %{}}
      {:ok, step} = StepStore.record_step_start(instance.id, node, 1)
      StepStore.record_step_complete(step, %{event_type: "signed_up"})

      conn = get(conn, "/api/v1/instances/#{instance.id}")
      body = json_response(conn, 200)

      assert body["data"]["id"] == instance.id
      assert length(body["steps"]) == 1
      assert hd(body["steps"])["node_type"] == "event_entry"
      assert hd(body["steps"])["status"] == "completed"
    end

    test "returns 404 for nonexistent instance", %{conn: conn} do
      conn = get(conn, "/api/v1/instances/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/v1/instances/:id/timeline" do
    test "returns ordered execution steps", %{conn: conn, flow: flow, tenant: tenant} do
      {:ok, instance} =
        InstanceStore.create_instance(%{
          flow_id: flow.id,
          version_number: 1,
          customer_id: "test_customer",
          tenant_id: tenant.id
        })

      node1 = %{"id" => "entry_1", "type" => "event_entry", "config" => %{}}
      node2 = %{"id" => "exit_1", "type" => "exit", "config" => %{}}

      {:ok, step1} = StepStore.record_step_start(instance.id, node1, 1)
      StepStore.record_step_complete(step1, %{})
      {:ok, step2} = StepStore.record_step_start(instance.id, node2, 1)
      StepStore.record_step_complete(step2, %{})

      conn = get(conn, "/api/v1/instances/#{instance.id}/timeline")
      body = json_response(conn, 200)

      assert length(body["data"]) == 2
      types = Enum.map(body["data"], & &1["node_type"])
      assert types == ["event_entry", "exit"]
    end
  end
end
