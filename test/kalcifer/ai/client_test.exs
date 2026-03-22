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
end
