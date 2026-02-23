# /new-endpoint — Create a new API endpoint

Create a new Phoenix API endpoint. The user provides: resource name, actions (CRUD and/or custom).

## Steps

### 1. Create the controller

File: `lib/kalcifer_web/controllers/{resource}_controller.ex`

```elixir
defmodule KalciferWeb.{Resource}Controller do
  use KalciferWeb, :controller

  alias Kalcifer.{Context}

  action_fallback KalciferWeb.FallbackController

  def index(conn, _params) do
    tenant = conn.assigns.current_tenant
    items = {Context}.list_{resources}(tenant.id)
    json(conn, %{data: Enum.map(items, &serialize/1)})
  end

  def create(conn, params) do
    tenant = conn.assigns.current_tenant

    with {:ok, item} <- {Context}.create_{resource}(tenant.id, params) do
      conn
      |> put_status(:created)
      |> json(%{data: serialize(item)})
    end
  end

  def show(conn, %{"id" => id}) do
    tenant = conn.assigns.current_tenant

    with {:ok, item} <- fetch_tenant_{resource}(tenant, id) do
      json(conn, %{data: serialize(item)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    tenant = conn.assigns.current_tenant

    with {:ok, item} <- fetch_tenant_{resource}(tenant, id),
         {:ok, updated} <- {Context}.update_{resource}(item, params) do
      json(conn, %{data: serialize(updated)})
    end
  end

  def delete(conn, %{"id" => id}) do
    tenant = conn.assigns.current_tenant

    with {:ok, item} <- fetch_tenant_{resource}(tenant, id),
         {:ok, _} <- {Context}.delete_{resource}(item) do
      send_resp(conn, :no_content, "")
    end
  end

  # --- Private ---

  defp fetch_tenant_{resource}(tenant, id) do
    case {Context}.get_{resource}(id) do
      %{tenant_id: tid} = item when tid == tenant.id -> {:ok, item}
      _ -> {:error, :not_found}
    end
  end

  defp serialize(item) do
    %{
      id: item.id
      # Add fields here
    }
  end
end
```

**Conventions**:
- Always use `action_fallback KalciferWeb.FallbackController`
- Always scope queries to `conn.assigns.current_tenant`
- Serialize explicitly (no Jason.Encoder derive)
- Use `with` chains for error handling

### 2. Add routes

Edit `lib/kalcifer_web/router.ex`. Add within the authenticated scope:

```elixir
# For standard CRUD:
resources "/{resources}", {Resource}Controller, except: [:new, :edit]

# For custom actions:
post "/{resources}/:id/{action}", {Resource}Controller, :{action}
```

### 3. Create controller test

File: `test/kalcifer_web/controllers/{resource}_controller_test.exs`

```elixir
defmodule KalciferWeb.{Resource}ControllerTest do
  use KalciferWeb.ConnCase, async: false

  import Kalcifer.Factory

  alias Kalcifer.Tenants

  @raw_api_key "test_api_key_{resource}"

  setup %{conn: conn} do
    hash = Tenants.hash_api_key(@raw_api_key)
    tenant = insert(:tenant, api_key_hash: hash)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@raw_api_key}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, tenant: tenant}
  end

  describe "index" do
    test "lists resources for tenant", %{conn: conn} do
      conn = get(conn, "/api/v1/{resources}")
      assert %{"data" => data} = json_response(conn, 200)
      assert is_list(data)
    end
  end

  # ... tests for each action
end
```

### 4. Create context functions if needed

If the context module doesn't have the required functions, add them following the pattern in `lib/kalcifer/flows.ex`.

### 5. Verify

```bash
mix test --trace test/kalcifer_web/controllers/{resource}_controller_test.exs
mix compile --warnings-as-errors
mix format
mix credo --strict
```
