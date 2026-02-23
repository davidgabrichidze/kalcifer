defmodule Kalcifer.Channels.Provider do
  @moduledoc false

  @type recipient :: map()
  @type message :: map()
  @type opts :: map()
  @type delivery_id :: String.t()

  @callback send_message(
              channel :: atom(),
              recipient :: recipient(),
              message :: message(),
              opts :: opts()
            ) :: {:ok, delivery_id()} | {:error, reason :: term()}

  @callback delivery_status(delivery_id()) ::
              {:ok, status :: String.t()} | {:error, reason :: term()}

  @optional_callbacks [delivery_status: 1]
end
