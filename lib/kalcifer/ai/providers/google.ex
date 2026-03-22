defmodule Kalcifer.AI.Providers.Google do
  @moduledoc """
  Google Gemini API adapter.

  Endpoint: POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
  Auth: API key as query parameter or x-goog-api-key header
  Streaming: :streamGenerateContent endpoint with SSE
  """

  @base_url "https://generativelanguage.googleapis.com/v1beta"

  def api_url(model \\ "gemini-2.5-flash") do
    "#{@base_url}/models/#{model}:generateContent"
  end

  def stream_url(model \\ "gemini-2.5-flash") do
    "#{@base_url}/models/#{model}:streamGenerateContent?alt=sse"
  end

  def headers(api_key) do
    [
      {"content-type", "application/json"},
      {"x-goog-api-key", api_key}
    ]
  end

  def auth_headers(api_key) do
    [{"x-goog-api-key", api_key}]
  end

  def build_body(messages, opts) do
    system_text = Keyword.get(opts, :system, "")

    contents = Enum.map(messages, &convert_message/1)

    body = %{contents: contents}

    body =
      if system_text != "" do
        Map.put(body, :system_instruction, %{parts: [%{text: system_text}]})
      else
        body
      end

    generation_config = %{
      maxOutputTokens: Keyword.get(opts, :max_tokens, 4096)
    }

    Map.put(body, :generationConfig, generation_config)
  end

  defp convert_message(%{role: "assistant", content: content}) when is_binary(content) do
    %{role: "model", parts: [%{text: content}]}
  end

  defp convert_message(%{role: "user", content: content}) when is_binary(content) do
    %{role: "user", parts: [%{text: content}]}
  end

  defp convert_message(%{role: "assistant", content: blocks}) when is_list(blocks) do
    parts =
      Enum.flat_map(blocks, fn
        %{"type" => "text", "text" => text} ->
          [%{text: text}]

        %{"type" => "tool_use", "name" => name, "input" => args} ->
          [%{functionCall: %{name: name, args: args}}]

        _ ->
          []
      end)

    %{role: "model", parts: parts}
  end

  defp convert_message(%{role: "user", content: blocks}) when is_list(blocks) do
    parts =
      Enum.flat_map(blocks, fn
        %{"type" => "text", "text" => text} ->
          [%{text: text}]

        %{"type" => "tool_result", "content" => content, "tool_use_id" => _id} ->
          [%{functionResponse: %{name: "tool", response: %{result: content}}}]

        _ ->
          []
      end)

    %{role: "user", parts: parts}
  end

  defp convert_message(msg), do: msg

  def extract_text(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    text =
      parts
      |> Enum.filter(fn p -> Map.has_key?(p, "text") end)
      |> Enum.map(fn p -> p["text"] end)
      |> Enum.join("")

    if text != "", do: {:ok, text}, else: {:error, :no_text_in_response}
  end

  def extract_text(body), do: {:error, {:unexpected_response, body}}

  def tool_use?(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    Enum.any?(parts, fn p -> Map.has_key?(p, "functionCall") end)
  end

  def tool_use?(_), do: false

  # Extract content in Anthropic-compatible format for the tool loop
  def extract_content(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    Enum.map(parts, fn
      %{"text" => text} ->
        %{"type" => "text", "text" => text}

      %{"functionCall" => %{"name" => name, "args" => args}} ->
        %{
          "type" => "tool_use",
          "id" => "call_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
          "name" => name,
          "input" => args
        }

      other ->
        %{"type" => "text", "text" => inspect(other)}
    end)
  end

  def extract_content(_), do: []

  def parse_stream_delta(%{
        "candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]
      }) do
    {:text_delta, text}
  end

  def parse_stream_delta(_), do: :ignore

  def build_tool_results(tool_results), do: tool_results
  def build_assistant_message(content), do: %{role: "assistant", content: content}

  # Convert Anthropic tool definitions to Gemini function declarations
  def convert_tools(tools) do
    declarations =
      Enum.map(tools, fn tool ->
        %{
          name: tool[:name] || tool["name"],
          description: tool[:description] || tool["description"] || "",
          parameters: tool[:input_schema] || tool["input_schema"] || %{}
        }
      end)

    [%{functionDeclarations: declarations}]
  end

  def default_env_key, do: "GOOGLE_API_KEY"
end
