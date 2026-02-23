defmodule Kalcifer.Engine.Jobs.ResumeFlowJob do
  @moduledoc false

  use Oban.Worker, queue: :delayed_resume, max_attempts: 3

  @impl true
  def perform(%Oban.Job{
        args: %{"instance_id" => instance_id, "node_id" => node_id, "trigger" => trigger}
      }) do
    trigger_atom = String.to_existing_atom(trigger)
    via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}

    case GenServer.whereis(via) do
      nil ->
        # Server not alive — snooze so Oban retries after RecoveryManager has a chance
        {:snooze, 30}

      _pid ->
        GenServer.cast(via, {:resume, node_id, trigger_atom})
        :ok
    end
  end
end
