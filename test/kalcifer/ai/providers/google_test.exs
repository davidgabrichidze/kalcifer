defmodule Kalcifer.AI.Providers.GoogleTest do
  use ExUnit.Case, async: true

  alias Kalcifer.AI.Providers.Google

  describe "build_body/2 tool round-trip" do
    test "a tool response carries the real tool name, not a placeholder" do
      messages = [
        %{role: "user", content: "list my flows"},
        %{
          role: "assistant",
          content: [
            %{"type" => "tool_use", "id" => "call_1", "name" => "list_flows", "input" => %{}}
          ]
        },
        %{
          role: "user",
          content: [
            %{"type" => "tool_result", "tool_use_id" => "call_1", "content" => "[]"}
          ]
        }
      ]

      %{contents: contents} = Google.build_body(messages, [])

      call = find_part(contents, :functionCall)
      response = find_part(contents, :functionResponse)

      assert call.name == "list_flows"
      # Gemini matches the response to the call by name; it must not be "tool".
      assert response.name == "list_flows"
      assert response.response == %{result: "[]"}
    end
  end

  defp find_part(contents, key) do
    Enum.find_value(contents, fn %{parts: parts} ->
      Enum.find_value(parts, fn part -> part[key] end)
    end)
  end
end
