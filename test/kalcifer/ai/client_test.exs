defmodule Kalcifer.AI.ClientTest do
  use ExUnit.Case, async: true

  alias Kalcifer.AI.Client

  describe "chat/2" do
    test "returns error when API key is not set" do
      messages = [%{role: "user", content: "hello"}]
      # Without a valid API key, the request will fail
      assert {:error, _reason} = Client.chat(messages)
    end
  end

  describe "chat_with_tools/5 round cap" do
    test "honors a caller-supplied max_tool_rounds cap" do
      parent = self()
      callback = fn event -> send(parent, event) end
      executor = fn _name, _input -> {:ok, ""} end

      # limit 0 => the loop hits the ceiling before any HTTP request, proving
      # the opt is threaded through (rather than the hardcoded default of 50).
      assert {:error, :max_tool_rounds} =
               Client.chat_with_tools(
                 [%{role: "user", content: "hi"}],
                 [],
                 executor,
                 callback,
                 max_tool_rounds: 0
               )

      assert_received {:error, _message}
    end
  end
end
