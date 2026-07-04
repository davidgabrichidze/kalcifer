defmodule Kalcifer.AI.Providers.AnthropicTest do
  use ExUnit.Case, async: true

  alias Kalcifer.AI.Providers.Anthropic

  describe "extract_text/1" do
    test "extracts text when the first block is a text block" do
      body = %{"content" => [%{"type" => "text", "text" => "hello"}]}
      assert {:ok, "hello"} = Anthropic.extract_text(body)
    end

    test "skips a leading thinking block (Sonnet 5+ adaptive thinking)" do
      body = %{
        "content" => [
          %{"type" => "thinking", "thinking" => "reasoning...", "signature" => "sig"},
          %{"type" => "text", "text" => "the answer"}
        ]
      }

      assert {:ok, "the answer"} = Anthropic.extract_text(body)
    end

    test "returns error when no text block is present" do
      body = %{"content" => [%{"type" => "thinking", "thinking" => "only thinking"}]}
      assert {:error, {:unexpected_response, _}} = Anthropic.extract_text(body)
    end

    test "returns error on a non-content body" do
      assert {:error, {:unexpected_response, _}} = Anthropic.extract_text(%{"error" => "boom"})
    end
  end

  describe "build_body/2" do
    test "does not send sampling or thinking parameters" do
      body = Anthropic.build_body([%{role: "user", content: "hi"}], [])

      refute Map.has_key?(body, :temperature)
      refute Map.has_key?(body, :top_p)
      refute Map.has_key?(body, :top_k)
      refute Map.has_key?(body, :thinking)
    end
  end
end
