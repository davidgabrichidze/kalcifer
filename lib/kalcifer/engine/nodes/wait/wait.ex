defmodule Kalcifer.Engine.Nodes.Wait.Wait do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, context) do
    if context["_dry_run"] do
      {:completed, %{dry_run: true, skipped_wait: config["duration"], waited: true}}
    else
      {:waiting, %{duration: config["duration"]}}
    end
  end

  @impl true
  def resume(_config, _context, :timer_expired) do
    {:completed, %{waited: true}}
  end

  def resume(_config, _context, _trigger) do
    {:failed, :unexpected_trigger}
  end

  # Reject an unparseable duration at preflight so the instance can't strand
  # in :waiting with no resume job ever scheduled.
  @impl true
  def validate(config) do
    case Kalcifer.Engine.Duration.to_seconds(config["duration"]) do
      {:ok, _seconds} -> :ok
      _ -> {:error, ["duration must be a value like \"3d\", \"2h\", \"30m\""]}
    end
  end

  @impl true
  def config_schema do
    %{"duration" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :wait
end
