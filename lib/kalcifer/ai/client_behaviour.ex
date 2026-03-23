defmodule Kalcifer.AI.ClientBehaviour do
  @moduledoc """
  Behaviour for AI client, allowing Mox-based testing of AI nodes.
  """

  @callback chat(messages :: list(map()), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @callback chat_with_tools(
              messages :: list(map()),
              tools :: list(map()),
              tool_executor :: (String.t(), map() -> {:ok, String.t()} | {:error, term()}),
              callback :: function(),
              opts :: keyword()
            ) :: {:ok, String.t()} | {:error, term()}
end
