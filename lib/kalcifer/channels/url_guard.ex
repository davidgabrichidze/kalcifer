defmodule Kalcifer.Channels.UrlGuard do
  @moduledoc """
  SSRF guard for operator-supplied outbound URLs (call_webhook / webhook
  provider). Rejects non-HTTP(S) schemes and any host that resolves to a
  private, loopback, link-local, or otherwise non-public address — so a
  flow can't be pointed at cloud metadata (169.254.169.254) or internal
  services.

  In dev/test, loopback is allowed so local webhook receivers work; set
  `config :kalcifer, :allow_private_webhooks, true` to permit it.
  """

  @doc "Returns :ok if the URL is safe to request, else {:error, reason}."
  def validate(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        validate_host(host)

      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        {:error, :invalid_url}

      %URI{scheme: scheme} when is_binary(scheme) ->
        {:error, :unsupported_scheme}

      _ ->
        {:error, :invalid_url}
    end
  end

  def validate(_url), do: {:error, :invalid_url}

  defp validate_host(host) do
    if allow_private?() do
      :ok
    else
      case resolve(host) do
        {:ok, addrs} ->
          if Enum.any?(addrs, &blocked?/1), do: {:error, :blocked_address}, else: :ok

        {:error, _} ->
          {:error, :unresolvable_host}
      end
    end
  end

  defp resolve(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, addr} ->
        {:ok, [addr]}

      {:error, _} ->
        with {:ok, v4} <- lookup(host, :inet) |> collect(),
             {:ok, v6} <- lookup(host, :inet6) |> collect() do
          case v4 ++ v6 do
            [] -> {:error, :nxdomain}
            addrs -> {:ok, addrs}
          end
        end
    end
  end

  defp lookup(host, family), do: :inet.getaddrs(String.to_charlist(host), family)

  # Absence of a record for one family isn't an error; missing both is.
  defp collect({:ok, addrs}), do: {:ok, addrs}
  defp collect({:error, _}), do: {:ok, []}

  # Loopback
  defp blocked?({127, _, _, _}), do: true
  defp blocked?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  # Private IPv4 (RFC1918)
  defp blocked?({10, _, _, _}), do: true
  defp blocked?({192, 168, _, _}), do: true
  defp blocked?({172, b, _, _}) when b >= 16 and b <= 31, do: true
  # Link-local / cloud metadata (169.254.0.0/16)
  defp blocked?({169, 254, _, _}), do: true
  # Carrier-grade NAT (100.64.0.0/10)
  defp blocked?({100, b, _, _}) when b >= 64 and b <= 127, do: true
  # Unspecified / this-host
  defp blocked?({0, _, _, _}), do: true
  # IPv6 unique-local (fc00::/7) and link-local (fe80::/10)
  defp blocked?({a, _, _, _, _, _, _, _}) when a >= 0xFC00 and a <= 0xFDFF, do: true
  defp blocked?({a, _, _, _, _, _, _, _}) when a >= 0xFE80 and a <= 0xFEBF, do: true
  # IPv4-mapped IPv6 (::ffff:a.b.c.d) — unwrap and re-check
  defp blocked?({0, 0, 0, 0, 0, 0xFFFF, g, h}) do
    blocked?({div(g, 256), rem(g, 256), div(h, 256), rem(h, 256)})
  end

  defp blocked?(_addr), do: false

  defp allow_private? do
    Application.get_env(:kalcifer, :allow_private_webhooks, false)
  end
end
