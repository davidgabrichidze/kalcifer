defmodule Kalcifer.Bugs.InvalidMigrationStrategyTest do
  @moduledoc """
  I5: Regression test for migration strategy validation.
  MigrationController validates strategy via validate_strategy/1 before
  passing to Migrator. Invalid values return 422.
  """
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Flows
  alias Kalcifer.Tenants

  @raw_api_key "invalid_strategy_test_key"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  defp wait_graph do
    %{
      "nodes" => [
        %{
          "id" => "entry_1",
          "type" => "event_entry",
          "position" => %{"x" => 0, "y" => 0},
          "config" => %{"event_type" => "signed_up"}
        },
        %{
          "id" => "wait_1",
          "type" => "wait_for_event",
          "position" => %{"x" => 100, "y" => 0},
          "config" => %{"event_type" => "email_opened", "timeout" => "3d"}
        },
        %{
          "id" => "exit_1",
          "type" => "exit",
          "position" => %{"x" => 200, "y" => 0},
          "config" => %{}
        }
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
        %{
          "id" => "e2",
          "source" => "wait_1",
          "target" => "exit_1",
          "branch" => "event_received"
        },
        %{"id" => "e3", "source" => "wait_1", "target" => "exit_1", "branch" => "timed_out"}
      ]
    }
  end

  test "migrate with invalid strategy should return 422, not crash with 500", %{
    conn: conn,
    tenant: tenant
  } do
    flow = insert(:flow, tenant: tenant)
    insert(:flow_version, flow: flow, version_number: 1, graph: wait_graph())
    {:ok, flow} = Flows.activate_flow(flow)

    {:ok, _v2} = Flows.create_version(flow, %{graph: wait_graph(), changelog: "v2"})

    conn_resp =
      post(conn, "/api/v1/flows/#{flow.id}/versions/2/migrate", %{
        "strategy" => "invalid_strategy_value"
      })

    assert conn_resp.status == 422
  end
end
