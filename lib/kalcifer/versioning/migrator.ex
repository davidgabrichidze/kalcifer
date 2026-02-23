defmodule Kalcifer.Versioning.Migrator do
  @moduledoc false

  alias Kalcifer.Engine.Persistence.InstanceStore
  alias Kalcifer.Flows
  alias Kalcifer.Versioning.NodeMapper

  def migrate(flow_id, from_version, to_version, strategy \\ "migrate_all") do
    with {:ok, old_graph} <- fetch_graph(flow_id, from_version),
         {:ok, new_graph} <- fetch_graph(flow_id, to_version) do
      node_map = NodeMapper.build_mapping(old_graph, new_graph)
      instances = InstanceStore.list_active_for_version(flow_id, from_version)
      result = migrate_instances(instances, new_graph, node_map, to_version, strategy)
      {:ok, result}
    end
  end

  defp migrate_instances(instances, new_graph, node_map, to_version, strategy) do
    empty = %{migrated: [], exited: [], skipped: [], failed: []}

    Enum.reduce(instances, empty, fn instance, acc ->
      case do_migrate_instance(instance, new_graph, node_map, to_version, strategy) do
        {:migrated, id} -> %{acc | migrated: [id | acc.migrated]}
        {:exited, id} -> %{acc | exited: [id | acc.exited]}
        {:skipped, id} -> %{acc | skipped: [id | acc.skipped]}
        {:failed, id, reason} -> %{acc | failed: [%{id: id, reason: reason} | acc.failed]}
      end
    end)
  end

  def rollback(flow_id, from_version, to_version) do
    migrate(flow_id, from_version, to_version, "migrate_all")
  end

  defp do_migrate_instance(instance, _new_graph, _node_map, _to_version, "new_entries_only") do
    {:skipped, instance.id}
  end

  defp do_migrate_instance(instance, new_graph, node_map, to_version, "migrate_all") do
    current_nodes = instance.current_nodes || []

    case NodeMapper.check_migration_safety(current_nodes, node_map) do
      {:unsafe, :on_removed_node, _ids} ->
        InstanceStore.exit_instance(instance, "node_removed_in_new_version")
        stop_flow_server(instance.id)
        {:exited, instance.id}

      :ok ->
        case migrate_single(instance, new_graph, node_map, to_version) do
          :ok -> {:migrated, instance.id}
          {:error, reason} -> {:failed, instance.id, reason}
        end
    end
  end

  defp do_migrate_instance(instance, _new_graph, _node_map, _to_version, strategy) do
    {:failed, instance.id, {:invalid_strategy, strategy}}
  end

  defp migrate_single(instance, new_graph, node_map, to_version) do
    case InstanceStore.migrate_instance(instance, to_version) do
      {:ok, _} ->
        hot_swap_flow_server(instance.id, new_graph, to_version, node_map)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp hot_swap_flow_server(instance_id, new_graph, new_version, node_map) do
    via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}

    case GenServer.whereis(via) do
      nil ->
        # Process not alive — DB already updated, recovery will use new version
        :ok

      _pid ->
        try do
          GenServer.call(via, {:migrate, new_graph, new_version, node_map}, 5000)
        catch
          :exit, _ -> :ok
        end
    end
  end

  defp stop_flow_server(instance_id) do
    via = {:via, Registry, {Kalcifer.Engine.ProcessRegistry, instance_id}}

    case GenServer.whereis(via) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  defp fetch_graph(flow_id, version_number) do
    case Flows.get_version(flow_id, version_number) do
      nil -> {:error, :version_not_found}
      version -> {:ok, version.graph}
    end
  end
end
