defmodule Kalcifer.Engine.Duration do
  @moduledoc false

  @units %{"s" => 1, "m" => 60, "h" => 3_600, "d" => 86_400, "w" => 604_800}

  def to_seconds(duration_string) when is_binary(duration_string) do
    case Regex.run(~r/^(\d+)(s|m|h|d|w)$/, duration_string) do
      [_, amount, unit] -> {:ok, String.to_integer(amount) * @units[unit]}
      _ -> {:error, :invalid_duration}
    end
  end

  def to_seconds(_), do: {:error, :invalid_duration}

  def to_datetime(duration_string) do
    with {:ok, seconds} <- to_seconds(duration_string) do
      {:ok, DateTime.add(DateTime.utc_now(), seconds, :second)}
    end
  end
end
