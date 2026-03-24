defmodule Kalcifer.AI.Providers.OpenAI do
  @moduledoc """
  OpenAI (ChatGPT) API adapter.

  Endpoint: POST https://api.openai.com/v1/chat/completions
  Auth: Authorization: Bearer <key>
  """

  @api_url "https://api.openai.com/v1/chat/completions"

  def api_url, do: @api_url

  def headers(api_key) do
    [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{api_key}"}
    ]
  end

  def auth_headers(api_key) do
    [{"authorization", "Bearer #{api_key}"}]
  end

  def build_body(messages, opts) do
    system_text = Keyword.get(opts, :system, "")

    # OpenAI uses a system message in the messages array
    system_msgs =
      if system_text != "" do
        [%{role: "system", content: system_text}]
      else
        []
      end

    converted =
      messages
      |> Enum.flat_map(fn msg ->
        case convert_message(msg) do
          list when is_list(list) -> list
          single -> [single]
        end
      end)

    %{
      model: Keyword.get(opts, :model, "gpt-4o-mini"),
      max_completion_tokens: Keyword.get(opts, :max_tokens, 4096),
      messages: system_msgs ++ converted
    }
  end

  # Convert Anthropic-style messages to OpenAI format
  defp convert_message(%{role: role, content: content}) when is_binary(content) do
    %{role: role, content: content}
  end

  defp convert_message(%{role: "assistant", content: blocks}) when is_list(blocks) do
    # Anthropic tool_use blocks → OpenAI tool_calls
    text_parts =
      blocks
      |> Enum.filter(fn b -> is_map(b) && b["type"] == "text" end)
      |> Enum.map(fn b -> b["text"] end)
      |> Enum.join("")

    tool_calls =
      blocks
      |> Enum.filter(fn b -> is_map(b) && b["type"] == "tool_use" end)
      |> Enum.map(fn b ->
        %{
          id: b["id"],
          type: "function",
          function: %{
            name: b["name"],
            arguments: Jason.encode!(b["input"])
          }
        }
      end)

    msg = %{role: "assistant"}
    msg = if text_parts != "", do: Map.put(msg, :content, text_parts), else: msg
    msg = if tool_calls != [], do: Map.put(msg, :tool_calls, tool_calls), else: msg
    msg
  end

  defp convert_message(%{role: "user", content: blocks}) when is_list(blocks) do
    # Anthropic tool_result blocks → OpenAI tool messages
    # This case is handled differently — we return a list of messages
    tool_results =
      Enum.filter(blocks, fn b -> is_map(b) && b["type"] == "tool_result" end)

    if tool_results != [] do
      # Return multiple messages (flatten later)
      Enum.map(tool_results, fn tr ->
        %{
          role: "tool",
          tool_call_id: tr["tool_use_id"],
          content: tr["content"] || ""
        }
      end)
    else
      text =
        blocks
        |> Enum.filter(fn b -> is_map(b) && b["type"] == "text" end)
        |> Enum.map(fn b -> b["text"] end)
        |> Enum.join("")

      %{role: "user", content: text}
    end
  end

  defp convert_message(msg), do: msg

  def extract_text(%{"choices" => [%{"message" => %{"content" => text}} | _]})
      when is_binary(text) do
    {:ok, text}
  end

  def extract_text(body), do: {:error, {:unexpected_response, body}}

  def tool_use?(%{"choices" => [%{"finish_reason" => "tool_calls"} | _]}), do: true
  def tool_use?(%{"choices" => [%{"message" => %{"tool_calls" => [_ | _]}} | _]}), do: true
  def tool_use?(_), do: false

  # Extract content in Anthropic-compatible format for the tool loop
  def extract_content(%{"choices" => [%{"message" => msg} | _]}) do
    blocks = []

    blocks =
      if msg["content"] do
        blocks ++ [%{"type" => "text", "text" => msg["content"]}]
      else
        blocks
      end

    blocks =
      if msg["tool_calls"] do
        tool_blocks =
          Enum.map(msg["tool_calls"], fn tc ->
            %{
              "type" => "tool_use",
              "id" => tc["id"],
              "name" => tc["function"]["name"],
              "input" => Jason.decode!(tc["function"]["arguments"])
            }
          end)

        blocks ++ tool_blocks
      else
        blocks
      end

    blocks
  end

  def extract_content(_), do: []

  def parse_stream_delta(%{"choices" => [%{"delta" => %{"content" => text}} | _]})
      when is_binary(text) do
    {:text_delta, text}
  end

  def parse_stream_delta(_), do: :ignore

  def build_tool_results(tool_results), do: tool_results

  def build_assistant_message(content), do: %{role: "assistant", content: content}

  # Convert Anthropic tool definitions to OpenAI function format
  def convert_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        type: "function",
        function: %{
          name: tool[:name] || tool["name"],
          description: tool[:description] || tool["description"] || "",
          parameters: tool[:input_schema] || tool["input_schema"] || %{}
        }
      }
    end)
  end

  def default_env_key, do: "OPENAI_API_KEY"
end
