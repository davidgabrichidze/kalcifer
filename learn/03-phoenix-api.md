# Phoenix Framework — API-Only Mode

## Context: How Kalcifer Uses Phoenix

Kalcifer uses Phoenix purely as an API server — no HTML templates, no LiveView, no asset pipeline. It receives JSON requests, authenticates via API key, processes them through the engine, and returns JSON responses. If you've used Express.js, Django REST Framework, FastAPI, or Gin, this maps directly.

Phoenix is not a monolithic framework like Rails — it's a set of composable libraries. Kalcifer uses: the router, controllers, JSON views, plugs (middleware), PubSub, and the endpoint (HTTP entrypoint). It does NOT use: channels (WebSocket), LiveView, Ecto integration (Ecto is used directly), or the HTML/template system.

## The Request Lifecycle

```
HTTP Request
  → Bandit (HTTP server, replaces Cowboy)
  → Endpoint (KalciferWeb.Endpoint)
    → Plug pipeline (telemetry, parsers, CORS)
  → Router (KalciferWeb.Router)
    → Pipeline plugs (api auth, rate limiting)
  → Controller
    → Context module (Kalcifer.Flows, Kalcifer.Marketing, etc.)
    → Response (JSON)
```

## Router — Route Definition

```elixir
defmodule KalciferWeb.Router do
  use KalciferWeb, :router

  # Pipeline = a named chain of plugs applied to a group of routes
  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug KalciferWeb.Plugs.ApiKeyAuth
  end

  pipeline :rate_limited do
    plug KalciferWeb.Plugs.RateLimiter
  end

  # Public routes (no auth)
  scope "/api/v1", KalciferWeb do
    pipe_through [:api]
    get "/health", HealthController, :index
    get "/health/metrics", HealthController, :metrics
  end

  # Authenticated routes
  scope "/api/v1", KalciferWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    resources "/flows", FlowController, except: [:new, :edit] do
      resources "/versions", FlowVersionController, only: [:index, :show, :create]
      post "/activate", FlowController, :activate
      post "/pause", FlowController, :pause
    end

    resources "/journeys", JourneyController, except: [:new, :edit]
    post "/trigger/:flow_id", TriggerController, :trigger
    post "/events", EventController, :create
  end
end
```

**Key differences from other frameworks:**
- `pipe_through` applies middleware to route groups (like Express router.use)
- `resources` generates RESTful routes (index, show, create, update, delete)
- `except: [:new, :edit]` drops HTML form routes (not needed for API)
- Nested resources for flow/versions relationship

**Underwater Rock**: Phoenix routing is compile-time. Routes are compiled into pattern-matching clauses — this means routing is extremely fast but you can't add routes at runtime. Changes require recompilation.

## Plugs — The Middleware System

Plugs are Phoenix's middleware. Every request passes through a chain of plugs. A plug is any module that implements `init/1` and `call/2`.

### API Key Authentication Plug

```elixir
defmodule KalciferWeb.Plugs.ApiKeyAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, tenant} <- Kalcifer.Tenants.authenticate_by_api_key(token) do
      conn
      |> assign(:current_tenant, tenant)
      |> Plug.Conn.put_private(:tenant_id, tenant.id)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.put_view(KalciferWeb.ErrorJSON)
        |> Phoenix.Controller.render("401.json")
        |> halt()  # CRITICAL: halt() stops the plug chain
    end
  end
end
```

**Underwater Rock**: Forgetting `halt()` after sending an error response means the request continues to the controller. Always `halt()` after unauthorized/forbidden responses.

**Underwater Rock**: `assign/3` puts values in `conn.assigns` — this is how you pass data from plugs to controllers. `conn.assigns.current_tenant` is available in every controller action.

### Rate Limiter Plug (ETS-Based)

```elixir
defmodule KalciferWeb.Plugs.RateLimiter do
  # Uses ETS for fast, in-memory rate counting
  # Bucket-based: resets every window (e.g., 60 seconds)
  # Keyed by {tenant_id, action}

  def call(conn, _opts) do
    tenant_id = conn.assigns[:current_tenant].id
    action = Phoenix.Controller.action_name(conn)

    case check_rate(tenant_id, action) do
      :ok -> conn
      :rate_limited ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "Rate limit exceeded"})
        |> halt()
    end
  end
end
```

## Controllers — Request Handling

```elixir
defmodule KalciferWeb.FlowController do
  use KalciferWeb, :controller

  alias Kalcifer.Flows

  # GET /api/v1/flows
  def index(conn, params) do
    tenant = conn.assigns.current_tenant
    flows = Flows.list_flows(tenant.id, params)
    json(conn, %{data: flows})
  end

  # POST /api/v1/flows
  def create(conn, %{"flow" => flow_params}) do
    tenant = conn.assigns.current_tenant

    case Flows.create_flow(tenant, flow_params) do
      {:ok, flow} ->
        conn
        |> put_status(:created)
        |> json(%{data: flow})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  # POST /api/v1/flows/:id/activate
  def activate(conn, %{"flow_id" => flow_id}) do
    tenant = conn.assigns.current_tenant

    case Flows.activate_flow(tenant.id, flow_id) do
      {:ok, flow} -> json(conn, %{data: flow})
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end
end
```

**Pattern**: Controllers are thin. They extract params, call a context module (like `Flows`), and format the response. Business logic lives in context modules, NEVER in controllers.

### Trigger Controller — Starting Flow Instances

```elixir
defmodule KalciferWeb.TriggerController do
  use KalciferWeb, :controller

  def trigger(conn, %{"flow_id" => flow_id} = params) do
    tenant = conn.assigns.current_tenant
    context = Map.get(params, "context", %{})
    customer_id = Map.get(params, "customer_id")

    case Kalcifer.Engine.trigger_flow(tenant.id, flow_id, customer_id, context) do
      {:ok, instance} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{instance_id: instance.id, status: instance.status}})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end
end
```

## JSON Encoding

Kalcifer uses Jason for JSON encoding. Phoenix automatically encodes response bodies via `json/2`.

```elixir
# In config.exs
config :phoenix, :json_library, Jason

# Ecto schemas need @derive to be JSON-encodable
defmodule Kalcifer.Flows.Flow do
  @derive {Jason.Encoder, only: [:id, :name, :status, :description, :inserted_at, :updated_at]}
  schema "flows" do
    # ...
  end
end
```

**Underwater Rock**: Without `@derive Jason.Encoder`, trying to `json(conn, flow)` will crash. You must explicitly list which fields to encode. This prevents accidentally leaking internal fields.

## Error Handling

```elixir
defmodule KalciferWeb.ErrorJSON do
  def render("404.json", _assigns) do
    %{error: "Not found"}
  end

  def render("401.json", _assigns) do
    %{error: "Unauthorized"}
  end

  def render("500.json", _assigns) do
    %{error: "Internal server error"}
  end
end

# In controllers, use FallbackController for consistent error handling
defmodule KalciferWeb.FallbackController do
  use KalciferWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> json(%{error: "Not found"})
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
  end
end
```

## Endpoint — The HTTP Entrypoint

```elixir
defmodule KalciferWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :kalcifer

  plug Plug.RequestId        # Generates unique request ID
  plug Plug.Telemetry        # Emits telemetry events for request timing
  plug Plug.Parsers,         # Parses JSON request bodies
    parsers: [:json],
    json_decoder: Jason
  plug Corsica,              # CORS headers
    origins: "*",
    allow_headers: ["authorization", "content-type"]
  plug KalciferWeb.Router    # Finally, routes to controller
end
```

**Underwater Rock**: Plug order in the endpoint matters. Telemetry must come before the router to capture full request time. CORS must come before routing to handle preflight OPTIONS requests.

## Bandit vs Cowboy

Kalcifer uses Bandit instead of Cowboy as the HTTP server. Bandit is a newer, pure-Elixir HTTP server that's faster and simpler. The switch is one line in config:

```elixir
config :kalcifer, KalciferWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter
```

From the application's perspective, they're interchangeable. Bandit has better HTTP/2 support and simpler internals.

## CORS with Corsica

```elixir
# In mix.exs
{:corsica, "~> 2.1"}

# Configured in the endpoint
plug Corsica,
  origins: "*",  # In production, restrict this!
  allow_headers: ["authorization", "content-type"],
  allow_methods: ["GET", "POST", "PUT", "PATCH", "DELETE"]
```

**Underwater Rock for Production**: Never use `origins: "*"` in production. Whitelist specific domains. Kalcifer's API is designed for server-to-server communication where CORS is less relevant, but browser-based admin UIs need proper CORS.

## Testing Phoenix Controllers

```elixir
defmodule KalciferWeb.FlowControllerTest do
  use KalciferWeb.ConnCase

  setup %{conn: conn} do
    tenant = insert(:tenant)
    conn = put_req_header(conn, "authorization", "Bearer #{tenant.raw_api_key}")
    {:ok, conn: conn, tenant: tenant}
  end

  test "creates flow", %{conn: conn, tenant: tenant} do
    params = %{"flow" => %{"name" => "Welcome Flow"}}

    conn = post(conn, ~p"/api/v1/flows", params)

    assert %{"data" => %{"id" => id, "name" => "Welcome Flow"}} = json_response(conn, 201)
    assert Flows.get_flow!(id).tenant_id == tenant.id
  end

  test "returns 401 without auth", %{conn: conn} do
    conn = delete_req_header(conn, "authorization")
    conn = get(conn, ~p"/api/v1/flows")
    assert json_response(conn, 401)
  end
end
```

## Key Takeaways

1. Phoenix in API mode is minimal — router, plugs, controllers, JSON. No magic.
2. Plugs are composable middleware. Authentication, rate limiting, logging — all plugs.
3. Controllers are thin dispatchers. Business logic lives in context modules.
4. `conn` (the connection struct) is immutable — each transformation returns a new conn.
5. `halt()` is critical in error-handling plugs to stop the pipeline.
6. JSON encoding requires explicit field lists via `@derive` — this is a feature, not a bug.

## Recommended Resources

- Phoenix official guides: hexdocs.pm/phoenix (specifically the API section)
- "Programming Phoenix 1.4" by Chris McCord, Bruce Tate, José Valim
- Phoenix API guide: hexdocs.pm/phoenix/api_only.html
