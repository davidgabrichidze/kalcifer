defmodule Kalcifer.Channels.ChannelSender do
  @moduledoc false

  alias Kalcifer.Channels
  alias Kalcifer.Channels.Jobs.SendMessageJob
  alias Kalcifer.Channels.ProviderRegistry

  def send(channel, config, context) do
    recipient = build_recipient(context)
    message = build_message(config)
    tenant_id = context["_tenant_id"]
    instance_id = context["_instance_id"]

    case ProviderRegistry.lookup(channel) do
      {:ok, _provider} ->
        {:ok, delivery} =
          Channels.create_delivery(%{
            channel: Atom.to_string(channel),
            recipient: recipient,
            message: message,
            instance_id: instance_id,
            tenant_id: tenant_id
          })

        provider_opts = Map.get(config, "provider_opts", %{})

        SendMessageJob.new(%{
          delivery_id: delivery.id,
          channel: Atom.to_string(channel),
          recipient: recipient,
          message: message,
          provider_opts: provider_opts
        })
        |> Oban.insert()

        {:completed,
         %{delivery_id: delivery.id, channel: Atom.to_string(channel), status: "pending"}}

      :error ->
        {:failed, {:no_provider, channel}}
    end
  end

  defp build_recipient(context) do
    %{
      "customer_id" => context["_customer_id"],
      "email" => context["_email"],
      "phone" => context["_phone"]
    }
  end

  defp build_message(config) do
    Map.take(config, ["template_id", "subject", "body", "url", "placement", "expiry"])
  end
end
