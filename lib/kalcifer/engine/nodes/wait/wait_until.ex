defmodule Kalcifer.Engine.Nodes.Wait.WaitUntil do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, context) do
    if context["_dry_run"] do
      {:completed, %{dry_run: true, skipped_wait_until: config["datetime"], waited: true}}
    else
      {:waiting, %{until: config["datetime"]}}
    end
  end

  @impl true
  def resume(_config, _context, :timer_expired) do
    {:completed, %{waited: true}}
  end

  def resume(_config, _context, _trigger) do
    {:failed, :unexpected_trigger}
  end

  # Reject a non-ISO8601 datetime at preflight so the instance can't strand
  # in :waiting with no resume job ever scheduled.
  @impl true
  def validate(config) do
    case DateTime.from_iso8601(to_string(config["datetime"])) do
      {:ok, _dt, _offset} -> :ok
      _ -> {:error, ["datetime must be ISO8601, e.g. \"2026-01-01T00:00:00Z\""]}
    end
  end

  @impl true
  def config_schema do
    %{"datetime" => %{"type" => "string", "required" => true, "format" => "iso8601"}}
  end

  @impl true
  def category, do: :wait
end
