defmodule Kalcifer.Engine.RecoveryManager do
  @moduledoc false

  use Task, restart: :temporary

  import Ecto.Query

  alias Kalcifer.Engine.FlowServer
  alias Kalcifer.Engine.Jobs.ResumeFlowJob
  alias Kalcifer.Engine.Persistence.InstanceStore
  alias Kalcifer.Flows
  alias Kalcifer.Repo

  require Logger

  def start_link(_opts) do
    Task.start_link(__MODULE__, :maybe_recover, [])
  end

  def maybe_recover do
    unless Application.get_env(:kalcifer, :skip_recovery, false) do
      recover()
    end
  end

  def recover do
    instances = InstanceStore.list_recoverable_instances()

    Enum.each(instances, fn instance ->
      case instance.status do
        "waiting" -> recover_waiting(instance)
        "running" -> mark_crashed(instance)
      end
    end)
  end

  defp recover_waiting(instance) do
    case load_graph(instance) do
      nil ->
        Logger.warning(
          "RecoveryManager: no graph found for instance #{instance.id}, marking crashed"
        )

        mark_crashed(instance)

      graph ->
        waiting_node_id = instance.context["_waiting_node_id"]
        scheduled_at_str = instance.context["_resume_scheduled_at"]

        args = %{
          recovery: true,
          instance_id: instance.id,
          flow_id: instance.flow_id,
          customer_id: instance.customer_id,
          tenant_id: instance.tenant_id,
          version_number: instance.version_number,
          graph: graph,
          current_nodes: instance.current_nodes,
          context: instance.context,
          waiting_node_id: waiting_node_id
        }

        case start_flow_server(args) do
          {:ok, _pid} ->
            ensure_resume_scheduled(instance, waiting_node_id, scheduled_at_str)

          {:error, reason} ->
            Logger.warning(
              "RecoveryManager: failed to start FlowServer for #{instance.id}: #{inspect(reason)}"
            )
        end
    end
  end

  defp start_flow_server(args) do
    DynamicSupervisor.start_child(
      Kalcifer.Engine.FlowSupervisor,
      {FlowServer, args}
    )
  end

  defp load_graph(instance) do
    case Flows.get_version(instance.flow_id, instance.version_number) do
      nil -> nil
      version -> version.graph
    end
  end

  defp ensure_resume_scheduled(instance, node_id, scheduled_at_str) do
    if has_pending_oban_job?(instance.id) do
      :ok
    else
      resume_or_reschedule(instance, node_id, scheduled_at_str)
    end
  end

  defp has_pending_oban_job?(instance_id) do
    Repo.exists?(
      from j in Oban.Job,
        where: j.worker == "Kalcifer.Engine.Jobs.ResumeFlowJob",
        where: j.state in ["scheduled", "available", "retryable"],
        where: fragment("? ->> 'instance_id' = ?", j.args, ^instance_id)
    )
  end

  defp resume_or_reschedule(instance, node_id, scheduled_at_str) do
    scheduled_at = parse_scheduled_at(scheduled_at_str)
    now = DateTime.utc_now()

    cond do
      is_nil(node_id) ->
        :ok

      is_nil(scheduled_at) || DateTime.compare(scheduled_at, now) != :gt ->
        via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance.id}}
        GenServer.cast(via, {:resume, node_id, :timer_expired})

      true ->
        %{instance_id: instance.id, node_id: node_id, trigger: "timer_expired"}
        |> ResumeFlowJob.new(scheduled_at: scheduled_at)
        |> Oban.insert()
    end
  end

  defp parse_scheduled_at(nil), do: nil

  defp parse_scheduled_at(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp mark_crashed(instance) do
    Logger.info("RecoveryManager: marking instance #{instance.id} as crashed")
    InstanceStore.mark_crashed(instance)
  end
end
