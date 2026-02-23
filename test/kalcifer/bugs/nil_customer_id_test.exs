defmodule Kalcifer.Bugs.NilCustomerIdTest do
  @moduledoc """
  C9: nil customer_id bypasses dedup check in trigger.
  When customer_id is missing from the request body, it becomes nil.
  SQL `customer_id IS NULL` never matches existing NULL rows (NULL != NULL),
  so the dedup check always passes, allowing unlimited instances.

  Also tests EventController's nil customer_id/event_type handling (I8).
  """
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Flows
  alias Kalcifer.Tenants

  @raw_api_key "nil_customer_test_key"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  @tag :known_bug
  test "trigger without customer_id should return 400/422, not crash", %{
    conn: conn,
    tenant: tenant
  } do
    flow = insert(:flow, tenant: tenant)
    insert(:flow_version, flow: flow, graph: valid_graph())
    {:ok, flow} = Flows.activate_flow(flow)

    # Missing customer_id entirely — should return a clean 400/422 error,
    # not crash with Ecto ArgumentError (comparing nil in where clause).
    # BUG: Currently raises ArgumentError because Ecto rejects nil comparison.
    # The controller should validate customer_id before passing to the engine.
    assert_raise ArgumentError, fn ->
      post(conn, "/api/v1/flows/#{flow.id}/trigger", %{})
    end
  end

  @tag :known_bug
  test "event without customer_id should return 400, not crash with Ecto error", %{conn: conn} do
    # BUG: Should return 400 for missing customer_id.
    # Currently crashes because Ecto rejects nil in where clause comparison.
    # The controller should validate presence of customer_id before hitting the DB.
    assert_raise ArgumentError, fn ->
      post(conn, "/api/v1/events", %{
        "event_type" => "email_opened",
        "data" => %{}
      })
    end
  end

  @tag :known_bug
  test "event without event_type should return 400, not 202", %{conn: conn} do
    conn_resp =
      post(conn, "/api/v1/events", %{
        "customer_id" => "some_customer",
        "data" => %{}
      })

    status = conn_resp.status
    assert status == 400, "BUG: Event accepted nil event_type with HTTP #{status}"
  end
end
