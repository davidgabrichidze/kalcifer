defmodule Kalcifer.Engine.LogHandler do
  @moduledoc """
  Erlang :logger handler that forwards log events to LogCollector.
  Attached in Application.start/2.
  """

  alias Kalcifer.Engine.LogCollector

  @doc "Handler callback invoked by :logger for each log event"
  def log(%{level: level, msg: msg, meta: meta}, _config) do
    message = format_message(msg)

    metadata = %{
      source: Map.get(meta, :application, nil),
      module: Map.get(meta, :mfa, nil) |> extract_module()
    }

    LogCollector.push(level, message, metadata)
  end

  defp format_message({:string, msg}), do: IO.chardata_to_string(msg)

  defp format_message({:report, report}) when is_map(report) do
    inspect(report, limit: 200)
  end

  defp format_message({:report, report}) when is_list(report) do
    inspect(report, limit: 200)
  end

  defp format_message(msg) when is_binary(msg), do: msg
  defp format_message(msg), do: inspect(msg, limit: 200)

  defp extract_module({mod, _fun, _arity}), do: mod
  defp extract_module(_), do: nil
end
