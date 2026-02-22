defmodule Kalcifer.Engine.FlowTrigger do
  @moduledoc false

  alias Kalcifer.Flows
  alias Kalcifer.Flows.FlowVersion
  alias Kalcifer.Repo

  def trigger(flow_id, customer_id, initial_context \\ %{}) do
    with {:ok, flow} <- fetch_active_flow(flow_id),
         {:ok, version} <- fetch_active_version(flow) do
      instance_id = Ecto.UUID.generate()

      args = %{
        instance_id: instance_id,
        flow_id: flow.id,
        customer_id: customer_id,
        tenant_id: flow.tenant_id,
        version_number: version.version_number,
        graph: version.graph,
        initial_context: initial_context
      }

      case DynamicSupervisor.start_child(
             Kalcifer.Engine.FlowSupervisor,
             {Kalcifer.Engine.FlowServer, args}
           ) do
        {:ok, _pid} -> {:ok, instance_id}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fetch_active_flow(flow_id) do
    case Flows.get_flow(flow_id) do
      %{status: "active"} = flow -> {:ok, flow}
      %{} -> {:error, :flow_not_active}
      nil -> {:error, :not_found}
    end
  end

  defp fetch_active_version(%{active_version_id: nil}), do: {:error, :no_active_version}

  defp fetch_active_version(flow) do
    case Repo.get(FlowVersion, flow.active_version_id) do
      nil -> {:error, :no_active_version}
      version -> {:ok, version}
    end
  end
end
