defmodule KalciferWeb.Plugs.DevOnlyTest do
  # async: false — toggles the global :allow_tenant_header flag.
  use KalciferWeb.ConnCase, async: false

  alias KalciferWeb.Plugs.DevOnly

  setup do
    original = Application.get_env(:kalcifer, :allow_tenant_header, false)
    on_exit(fn -> Application.put_env(:kalcifer, :allow_tenant_header, original) end)
    :ok
  end

  test "passes the request through when the dev flag is on", %{conn: conn} do
    Application.put_env(:kalcifer, :allow_tenant_header, true)
    conn = DevOnly.call(conn, [])
    refute conn.halted
  end

  test "responds 404 and halts when the dev flag is off", %{conn: conn} do
    Application.put_env(:kalcifer, :allow_tenant_header, false)
    conn = DevOnly.call(conn, [])
    assert conn.halted
    assert conn.status == 404
  end
end
