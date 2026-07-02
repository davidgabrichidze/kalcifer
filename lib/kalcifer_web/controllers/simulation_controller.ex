defmodule KalciferWeb.SimulationController do
  use KalciferWeb, :controller

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Flows
  alias KalciferWeb.TenantResolver

  @doc """
  POST /api/v1/flows/:flow_id/simulate

  Runs a dry-run simulation of a flow and streams step results as SSE.

  Accepts:
    - `customer_id` (optional): simulated customer (default: "sim_customer")
    - `context` (optional): initial context map

  SSE events:
    - `sim_start`   — instance_id, flow info
    - `sim_step`    — node_id, node_type, status, output
    - `sim_done`    — final status, step_count, duration_ms
    - `error`       — error message
  """
  def create(conn, %{"flow_id" => flow_id} = params) do
    # Resolve the tenant before opening the stream so a foreign flow_id is
    # rejected as not-found rather than simulated (leaking its graph + output).
    tenant = TenantResolver.resolve(conn)

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    customer_id = params["customer_id"] || "sim_customer"
    initial_context = params["context"] || %{}

    case resolve_flow_and_version(flow_id, tenant) do
      {:ok, flow, version} ->
        run_simulation(conn, flow, version, customer_id, initial_context)

      {:error, reason} ->
        chunk_sse(conn, "error", %{message: error_message(reason)})
        conn
    end
  end

  defp run_simulation(conn, flow, version, customer_id, initial_context) do
    instance_id = Ecto.UUID.generate()
    started_at = System.monotonic_time(:millisecond)

    # Subscribe to instance events
    Phoenix.PubSub.subscribe(Kalcifer.PubSub, "instance:#{instance_id}")

    chunk_sse(conn, "sim_start", %{
      instance_id: instance_id,
      flow_id: flow.id,
      flow_name: flow.name,
      version_number: version.version_number,
      node_count: length(version.graph["nodes"] || [])
    })

    args = %{
      instance_id: instance_id,
      flow_id: flow.id,
      customer_id: customer_id,
      tenant_id: flow.tenant_id,
      version_number: version.version_number,
      graph: version.graph,
      initial_context: initial_context,
      dry_run: true
    }

    case DynamicSupervisor.start_child(
           Kalcifer.Engine.FlowSupervisor,
           {FlowServer, args}
         ) do
      {:ok, _pid} ->
        conn = listen_sim_events(conn, %{started_at: started_at, step_count: 0})
        conn

      {:error, reason} ->
        chunk_sse(conn, "error", %{message: "Failed to start simulation: #{inspect(reason)}"})
        conn
    end
  end

  defp listen_sim_events(conn, state) do
    receive do
      %{type: "node_executed", payload: payload} ->
        step_count = state.step_count + 1

        chunk_sse(conn, "sim_step", %{
          step: step_count,
          node_id: payload.node_id,
          node_type: payload.node_type,
          status: "completed",
          result: Map.get(payload, :result)
        })

        listen_sim_events(conn, %{state | step_count: step_count})

      %{type: "node_waiting", payload: payload} ->
        # In dry_run this shouldn't happen, but handle it
        step_count = state.step_count + 1

        chunk_sse(conn, "sim_step", %{
          step: step_count,
          node_id: payload.node_id,
          node_type: payload.node_type,
          status: "waiting"
        })

        listen_sim_events(conn, %{state | step_count: step_count})

      %{type: "instance_completed"} ->
        elapsed = System.monotonic_time(:millisecond) - state.started_at

        chunk_sse(conn, "sim_done", %{
          status: "completed",
          step_count: state.step_count,
          duration_ms: elapsed
        })

        conn

      %{type: "instance_failed"} ->
        elapsed = System.monotonic_time(:millisecond) - state.started_at

        chunk_sse(conn, "sim_done", %{
          status: "failed",
          step_count: state.step_count,
          duration_ms: elapsed
        })

        conn
    after
      30_000 ->
        chunk_sse(conn, "error", %{message: "Simulation timeout"})
        conn
    end
  end

  # Public for testing: resolves a flow to a runnable version, scoped to the
  # tenant. A flow owned by another tenant reads as not-found (no probing).
  @doc false
  def resolve_flow_and_version(flow_id, tenant) do
    case Flows.get_flow(flow_id) do
      %{tenant_id: tenant_id} when tenant_id != tenant.id -> {:error, :not_found}
      nil -> {:error, :not_found}
      %{status: "draft"} = flow -> draft_version(flow)
      flow -> active_version(flow)
    end
  end

  # Drafts run on their latest version.
  defp draft_version(flow) do
    case get_latest_version(flow.id) do
      nil -> {:error, :no_version}
      version -> {:ok, flow, version}
    end
  end

  # Active/paused flows run on their pinned active version.
  defp active_version(%{active_version_id: nil}), do: {:error, :no_active_version}

  defp active_version(flow) do
    case Kalcifer.Repo.get(Kalcifer.Flows.FlowVersion, flow.active_version_id) do
      nil -> {:error, :no_active_version}
      version -> {:ok, flow, version}
    end
  end

  defp get_latest_version(flow_id) do
    import Ecto.Query

    Kalcifer.Flows.FlowVersion
    |> where(flow_id: ^flow_id)
    |> order_by(desc: :version_number)
    |> limit(1)
    |> Kalcifer.Repo.one()
  end

  defp error_message(:not_found), do: "Flow not found"
  defp error_message(:no_version), do: "Flow has no versions"
  defp error_message(:no_active_version), do: "Flow has no active version"

  defp chunk_sse(conn, event, data) do
    payload = "event: #{event}\ndata: #{Jason.encode!(data)}\n\n"

    case chunk(conn, payload) do
      {:ok, _conn} -> conn
      {:error, :closed} -> conn
    end
  end
end
