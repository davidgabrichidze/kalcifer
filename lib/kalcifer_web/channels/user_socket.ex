defmodule KalciferWeb.UserSocket do
  use Phoenix.Socket

  channel "flow:*", KalciferWeb.FlowChannel
  channel "tenant:*", KalciferWeb.FlowChannel
  channel "instance:*", KalciferWeb.FlowChannel

  @impl true
  def connect(%{"api_key" => raw_key}, socket, _connect_info) do
    hash = :crypto.hash(:sha256, raw_key) |> Base.encode16(case: :lower)

    case Kalcifer.Repo.get_by(Kalcifer.Tenants.Tenant, api_key_hash: hash) do
      nil -> :error
      tenant -> {:ok, assign(socket, :tenant_id, tenant.id)}
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "tenant_socket:#{socket.assigns.tenant_id}"
end
