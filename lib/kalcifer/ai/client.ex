defmodule Kalcifer.AI.Client do
  @moduledoc """
  Claude API client with streaming support.

  Sends messages to the Anthropic Messages API and streams
  the response back as a series of text deltas.

  Uses Finch directly for streaming (reliable chunk-by-chunk callbacks)
  and Req for non-streaming requests.
  """

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @max_tokens 4096

  @type message :: %{role: String.t(), content: String.t()}
  @type stream_event :: {:text_delta, String.t()} | {:done, String.t()} | {:error, term()}

  @doc """
  Sends a chat request and collects the full response (non-streaming).
  Returns `{:ok, response_text}` or `{:error, reason}`.
  """
  @spec chat(list(message()), keyword()) :: {:ok, String.t()} | {:error, term()}
  def chat(messages, opts \\ []) do
    system = Keyword.get(opts, :system, default_system_prompt())

    body = %{
      model: Keyword.get(opts, :model, @model),
      max_tokens: Keyword.get(opts, :max_tokens, @max_tokens),
      system: system,
      messages: messages
    }

    case Req.post(@api_url,
           json: body,
           headers: auth_headers(),
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        {:ok, text}

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("Claude API error: status=#{status} body=#{inspect(resp_body)}")
        {:error, {:api_error, status, resp_body}}

      {:error, reason} ->
        Logger.error("Claude API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sends a chat request with streaming via Finch.
  Calls `callback` for each text delta.
  Returns `{:ok, full_text}` or `{:error, reason}`.

  The callback receives `{:text_delta, chunk}` for each piece of text.
  """
  @spec stream(list(message()), (stream_event() -> any()), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def stream(messages, callback, opts \\ []) do
    system = Keyword.get(opts, :system, default_system_prompt())

    body =
      Jason.encode!(%{
        model: Keyword.get(opts, :model, @model),
        max_tokens: Keyword.get(opts, :max_tokens, @max_tokens),
        system: system,
        messages: messages,
        stream: true
      })

    headers = [
      {"content-type", "application/json"},
      {"x-api-key", api_key()},
      {"anthropic-version", "2023-06-01"}
    ]

    # acc = {status, sse_buffer, text_chunks}
    initial_acc = {nil, "", []}

    req = Finch.build(:post, @api_url, headers, body)

    handler = fn chunk, acc -> stream_handler(callback, chunk, acc) end

    case Finch.stream(req, Kalcifer.Finch, initial_acc, handler,
           receive_timeout: 120_000
         ) do
      {:ok, {200, _buffer, chunks}} ->
        full_text = chunks |> Enum.reverse() |> IO.iodata_to_binary()
        callback.({:done, full_text})
        {:ok, full_text}

      {:ok, {status, _buffer, _chunks}} ->
        Logger.error("Claude API stream error: status=#{status}")
        callback.({:error, "API error #{status}"})
        {:error, {:api_error, status}}

      {:error, reason} ->
        Logger.error("Claude API stream failed: #{inspect(reason)}")
        callback.({:error, inspect(reason)})
        {:error, reason}
    end
  end

  # Finch stream handler — receives {:status, _}, {:headers, _}, {:data, _}
  defp stream_handler(_callback, {:status, status}, {_old_status, buffer, chunks}) do
    {status, buffer, chunks}
  end

  defp stream_handler(_callback, {:headers, _headers}, acc), do: acc

  defp stream_handler(callback, {:data, data}, {status, buffer, chunks}) do
    new_buffer = buffer <> data
    # Split on newline; last part might be incomplete
    parts = String.split(new_buffer, "\n")
    {complete_lines, [remaining]} = Enum.split(parts, -1)

    new_chunks =
      Enum.reduce(complete_lines, chunks, fn line, acc ->
        case parse_sse_line(line) do
          {:content_block_delta, text} ->
            callback.({:text_delta, text})
            [text | acc]

          _other ->
            acc
        end
      end)

    {status, remaining, new_chunks}
  end

  defp parse_sse_line("data: " <> json_str) do
    case Jason.decode(json_str) do
      {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
        {:content_block_delta, text}

      {:ok, %{"type" => type}} ->
        {:event, type}

      _ ->
        :ignore
    end
  end

  defp parse_sse_line(_), do: :ignore

  defp auth_headers do
    [
      {"x-api-key", api_key()},
      {"anthropic-version", "2023-06-01"}
    ]
  end

  defp api_key do
    Application.get_env(:kalcifer, __MODULE__, [])
    |> Keyword.get(:api_key, System.get_env("ANTHROPIC_API_KEY", ""))
  end

  defp default_system_prompt do
    """
    You are Kalcifer (კალციფერი), the living heart of a flow orchestration engine.
    You help operators build, debug, and optimize automation flows.
    You speak Georgian when spoken to in Georgian, and English otherwise.
    Be concise, warm, and helpful. Use your knowledge of the flow engine
    to give specific, actionable answers.

    Georgian transliteration rules (STRICT):
    - "flow" → "ფლოუ" (NEVER "ფლო")
    - "workflow" → "ვორკფლოუ"
    - Use "პროცესი" as a Georgian alternative when appropriate.
    - Technical English terms (API, webhook, node, trigger) keep in English or use
      established Georgian transliterations, never invent incorrect ones.
    """
  end
end
