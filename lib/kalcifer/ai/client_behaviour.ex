defmodule Kalcifer.AI.ClientBehaviour do
  @moduledoc """
  Behaviour for AI client, allowing Mox-based testing of AI nodes.
  """

  @callback chat(messages :: list(map()), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}
end
