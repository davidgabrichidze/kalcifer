defmodule Kalcifer.AI.Providers.Anthropic do
  @moduledoc """
  Anthropic (Claude) API adapter.

  Endpoint: POST https://api.anthropic.com/v1/messages
  Auth: x-api-key header + anthropic-version header
  """

  @api_url "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"

  def api_url, do: @api_url

  def headers(api_key) do
    [
      {"content-type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", @anthropic_version}
    ]
  end

  def auth_headers(api_key) do
    [
      {"x-api-key", api_key},
      {"anthropic-version", @anthropic_version}
    ]
  end

  def build_body(messages, opts) do
    %{
      model: Keyword.get(opts, :model, "claude-haiku-4-5-20251001"),
      max_tokens: Keyword.get(opts, :max_tokens, 4096),
      system: Keyword.get(opts, :system, ""),
      messages: messages
    }
  end

  # Extract text from Anthropic response format. Newer models (Sonnet 5+)
  # run adaptive thinking by default, so the first content block may be a
  # thinking block — find the first text block instead of assuming position.
  def extract_text(%{"content" => content} = body) when is_list(content) do
    content
    |> Enum.find_value(fn
      %{"type" => "text", "text" => text} -> {:ok, text}
      %{"text" => text} = block when not is_map_key(block, "type") -> {:ok, text}
      _ -> nil
    end)
    |> case do
      nil -> {:error, {:unexpected_response, body}}
      ok -> ok
    end
  end

  def extract_text(body), do: {:error, {:unexpected_response, body}}

  # Check if response wants tool use
  def tool_use?(%{"stop_reason" => "tool_use"}), do: true
  def tool_use?(_), do: false

  def extract_content(%{"content" => content}), do: content
  def extract_content(_), do: []

  # Parse SSE stream delta
  def parse_stream_delta(%{"type" => "content_block_delta", "delta" => %{"text" => text}}) do
    {:text_delta, text}
  end

  def parse_stream_delta(%{"type" => type}), do: {:event, type}
  def parse_stream_delta(_), do: :ignore

  # Build tool results for next round (Anthropic native format)
  def build_tool_results(tool_results), do: tool_results

  # Build assistant message for tool loop continuation
  def build_assistant_message(content), do: %{role: "assistant", content: content}

  def default_env_key, do: "ANTHROPIC_API_KEY"
end
