defmodule KalciferWeb.Plugs.RateLimiter do
  @moduledoc false

  import Plug.Conn

  @default_limits %{trigger: {100, 60}, events: {1000, 60}, default: {500, 60}}

  def init(opts), do: opts

  def call(conn, opts) do
    case conn.assigns[:current_tenant] do
      nil ->
        conn

      tenant ->
        action = Keyword.get(opts, :action, :default)
        {max_requests, window_seconds} = get_limit(action)

        bucket_key = "#{tenant.id}:#{action}"

        case check_rate(bucket_key, max_requests, window_seconds) do
          {:allow, _count} ->
            conn

          {:deny, retry_after} ->
            conn
            |> put_resp_header("retry-after", to_string(retry_after))
            |> put_status(:too_many_requests)
            |> Phoenix.Controller.json(%{
              error: "rate_limit_exceeded",
              retry_after: retry_after
            })
            |> halt()
        end
    end
  end

  defp get_limit(action) do
    config = Application.get_env(:kalcifer, :rate_limits, @default_limits)
    Map.get(config, action, @default_limits.default)
  end

  defp check_rate(key, max_requests, window_seconds) do
    table = ensure_table()
    now = System.system_time(:second)
    window_start = now - window_seconds

    # Clean old entries and count current window
    case :ets.lookup(table, key) do
      [{^key, timestamps}] ->
        active = Enum.filter(timestamps, &(&1 > window_start))

        if length(active) >= max_requests do
          oldest = Enum.min(active)
          retry_after = oldest + window_seconds - now
          {:deny, max(retry_after, 1)}
        else
          :ets.insert(table, {key, [now | active]})
          {:allow, length(active) + 1}
        end

      [] ->
        :ets.insert(table, {key, [now]})
        {:allow, 1}
    end
  end

  defp ensure_table do
    case :ets.whereis(:kalcifer_rate_limits) do
      :undefined ->
        :ets.new(:kalcifer_rate_limits, [:set, :public, :named_table])

      _ref ->
        :kalcifer_rate_limits
    end
  end
end
