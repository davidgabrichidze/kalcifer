defmodule Kalcifer.Analytics.TelemetryForwarder do
  @moduledoc """
  Attaches to the engine's telemetry events and forwards them to the
  Analytics.Collector for batched stats aggregation. Dry-run executions
  are excluded so simulations never pollute analytics.
  """

  alias Kalcifer.Analytics.Collector

  @handler_id "kalcifer-analytics-forwarder"

  @events [
    [:kalcifer, :step, :complete],
    [:kalcifer, :instance, :entered],
    [:kalcifer, :instance, :completed],
    [:kalcifer, :instance, :failed]
  ]

  def attach do
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil)
  end

  def handle_event(_event, _measurements, %{dry_run: true}, _config), do: :ok

  def handle_event([:kalcifer, :step, :complete], _measurements, metadata, _config) do
    with server when server != :disabled <- collector() do
      Collector.record_step(server, %{
        flow_id: metadata.flow_id,
        version_number: metadata.version_number,
        node_id: metadata.node_id,
        status: metadata.status,
        branch_key: metadata.branch_key
      })
    end
  end

  def handle_event([:kalcifer, :instance, type], _measurements, metadata, _config) do
    with server when server != :disabled <- collector() do
      Collector.record_instance(server, %{
        flow_id: metadata.flow_id,
        version_number: metadata.version_number,
        type: type
      })
    end
  end

  # :disabled in the test env keeps engine tests from feeding the global
  # collector, whose flush would then write outside the SQL sandbox.
  defp collector do
    Application.get_env(:kalcifer, :analytics_collector, Collector)
  end
end
