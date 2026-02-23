defmodule KalciferWeb.Plugs.RateLimiterTest do
  use Kalcifer.DataCase, async: false

  import Plug.Conn
  import Phoenix.ConnTest

  alias KalciferWeb.Plugs.RateLimiter

  defp build_conn_with_tenant(tenant_id) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> assign(:current_tenant, %{id: tenant_id})
  end

  setup do
    # Clean up ETS table between tests
    case :ets.whereis(:kalcifer_rate_limits) do
      :undefined -> :ok
      _ref -> :ets.delete_all_objects(:kalcifer_rate_limits)
    end

    # Override rate limits for testing
    Application.put_env(:kalcifer, :rate_limits, %{
      trigger: {3, 60},
      default: {5, 60}
    })

    on_exit(fn ->
      Application.delete_env(:kalcifer, :rate_limits)
    end)

    :ok
  end

  test "allows requests under the limit" do
    conn = build_conn_with_tenant("tenant_rate_1")
    result = RateLimiter.call(conn, action: :trigger)
    refute result.halted
  end

  test "blocks requests over the limit" do
    conn = build_conn_with_tenant("tenant_rate_2")

    # Use up the limit (3 for trigger)
    Enum.each(1..3, fn _ ->
      RateLimiter.call(conn, action: :trigger)
    end)

    # Fourth request should be blocked
    result = RateLimiter.call(conn, action: :trigger)
    assert result.halted
    assert result.status == 429
    assert get_resp_header(result, "retry-after") != []
  end

  test "different tenants have separate limits" do
    conn1 = build_conn_with_tenant("tenant_rate_3")
    conn2 = build_conn_with_tenant("tenant_rate_4")

    # Use up tenant1's limit
    Enum.each(1..3, fn _ ->
      RateLimiter.call(conn1, action: :trigger)
    end)

    # Tenant2 should still be allowed
    result = RateLimiter.call(conn2, action: :trigger)
    refute result.halted
  end

  test "passes through when no tenant is assigned" do
    conn = build_conn()
    result = RateLimiter.call(conn, action: :trigger)
    refute result.halted
  end
end
