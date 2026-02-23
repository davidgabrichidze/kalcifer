defmodule Kalcifer.Engine.FrequencyCapHelpers do
  @moduledoc false

  alias Kalcifer.Engine.Duration

  @channel_node_types %{
    "email" => ["send_email"],
    "sms" => ["send_sms"],
    "push" => ["send_push"],
    "whatsapp" => ["send_whatsapp"],
    "in_app" => ["send_in_app"],
    "webhook" => ["call_webhook"],
    "all" => [
      "send_email",
      "send_sms",
      "send_push",
      "send_whatsapp",
      "send_in_app",
      "call_webhook"
    ]
  }

  def channel_node_types, do: @channel_node_types

  @spec parse_time_window(String.t()) :: {:ok, DateTime.t()} | {:error, term()}
  def parse_time_window(raw) when is_binary(raw) do
    case Duration.to_seconds(raw) do
      {:ok, seconds} -> {:ok, DateTime.add(DateTime.utc_now(), -seconds, :second)}
      _ -> {:error, :invalid_time_window}
    end
  end

  def parse_time_window(_), do: {:error, :invalid_time_window}

  @spec resolve_channel_types(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def resolve_channel_types(channel) do
    case Map.get(@channel_node_types, channel) do
      nil -> {:error, {:unknown_channel, channel}}
      types -> {:ok, types}
    end
  end
end
