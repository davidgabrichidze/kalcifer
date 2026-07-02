defmodule Kalcifer.Engine.NodeExecutor do
  @moduledoc false

  alias Kalcifer.Engine.NodeRegistry

  def execute(node, context, registry \\ NodeRegistry) do
    with {:ok, module} <- lookup(registry, node["type"]) do
      safe_call(fn -> module.execute(node["config"] || %{}, context) end)
    end
  end

  def resume(node, context, trigger, registry \\ NodeRegistry) do
    with {:ok, module} <- lookup(registry, node["type"]) do
      safe_call(fn -> module.resume(node["config"] || %{}, context, trigger) end)
    end
  end

  defp lookup(registry, type) do
    case registry.lookup(type) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_node_type, type}}
    end
  end

  defp safe_call(fun) do
    fun.()
  rescue
    error ->
      {:failed,
       %{
         reason: Exception.message(error),
         stacktrace: Exception.format_stacktrace(__STACKTRACE__)
       }}
  catch
    # A node that exits or throws (e.g. an unwrapped gen_tcp/HTTP client exit)
    # would otherwise crash the FlowServer, restart it with the same args, and
    # crash-loop on the already-inserted instance row. Contain it as a failure.
    kind, value ->
      {:failed,
       %{
         reason: "node #{kind}: #{inspect(value)}",
         stacktrace: Exception.format_stacktrace(__STACKTRACE__)
       }}
  end
end
