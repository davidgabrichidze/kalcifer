defmodule Kalcifer.AI.Client do
  @moduledoc """
  Claude API client with streaming and tool use support.

  Uses Finch directly for streaming (reliable chunk-by-chunk callbacks)
  and Req for non-streaming requests (including tool use rounds).
  """

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @max_tokens 4096
  @max_tool_rounds 5

  @type message :: %{role: String.t(), content: String.t() | list()}
  @type stream_event ::
          {:text_delta, String.t()}
          | {:tool_use, String.t(), String.t(), map()}
          | {:tool_result, String.t(), String.t()}
          | {:done, String.t()}
          | {:error, term()}

  # ── Non-streaming chat (no tools) ─────────────────────────────

  @doc """
  Sends a chat request and collects the full response (non-streaming).
  Returns `{:ok, response_text}` or `{:error, reason}`.
  """
  @spec chat(list(message()), keyword()) :: {:ok, String.t()} | {:error, term()}
  def chat(messages, opts \\ []) do
    body = base_body(messages, opts)

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

  # ── Streaming chat (no tools) ─────────────────────────────────

  @doc """
  Sends a chat request with streaming via Finch.
  Calls `callback` for each text delta.
  Returns `{:ok, full_text}` or `{:error, reason}`.
  """
  @spec stream(list(message()), (stream_event() -> any()), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def stream(messages, callback, opts \\ []) do
    body = base_body(messages, opts) |> Map.put(:stream, true)
    do_stream(body, callback)
  end

  # ── Chat with tools (non-streaming tool rounds, streaming final) ──

  @doc """
  Chat with tool use support. Handles the tool loop:

  1. Send messages + tool definitions to Claude (non-streaming)
  2. If response contains tool_use blocks, execute tools via `tool_executor`
  3. Append tool results, send again
  4. Repeat until text-only response (max #{@max_tool_rounds} rounds)
  5. Stream the final text response

  `tool_executor` is `fn(name, input) -> {:ok, result} | {:error, reason}`
  `callback` receives stream events for the UI.
  """
  @spec chat_with_tools(
          list(message()),
          list(map()),
          (String.t(), map() -> {:ok, String.t()} | {:error, String.t()}),
          (stream_event() -> any()),
          keyword()
        ) :: {:ok, String.t()} | {:error, term()}
  def chat_with_tools(messages, tools, tool_executor, callback, opts \\ []) do
    tool_loop(messages, tools, tool_executor, callback, opts, 0)
  end

  defp tool_loop(messages, tools, tool_executor, callback, opts, round)
       when round < @max_tool_rounds do
    body =
      base_body(messages, opts)
      |> Map.put(:tools, tools)

    case Req.post(@api_url,
           json: body,
           headers: auth_headers(),
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: %{"content" => content, "stop_reason" => stop_reason}}} ->
        if stop_reason == "tool_use" do
          # Extract tool_use blocks and execute them
          tool_results = process_tool_calls(content, tool_executor, callback)

          # Build continuation: assistant message + tool results
          next_messages =
            messages ++
              [%{role: "assistant", content: content}] ++
              [%{role: "user", content: tool_results}]

          tool_loop(next_messages, tools, tool_executor, callback, opts, round + 1)
        else
          # Final response — re-send with streaming for proper UX
          stream_body =
            base_body(messages, opts)
            |> Map.put(:tools, tools)
            |> Map.put(:stream, true)

          do_stream(stream_body, callback)
        end

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("Claude API tool error: status=#{status}")
        callback.({:error, "API error #{status}: #{inspect(resp_body)}"})
        {:error, {:api_error, status, resp_body}}

      {:error, reason} ->
        Logger.error("Claude API tool request failed: #{inspect(reason)}")
        callback.({:error, inspect(reason)})
        {:error, reason}
    end
  end

  defp tool_loop(_messages, _tools, _executor, callback, _opts, _round) do
    callback.({:error, "Too many tool rounds"})
    {:error, :max_tool_rounds}
  end

  defp process_tool_calls(content, tool_executor, callback) do
    tool_uses =
      Enum.filter(content, fn block -> block["type"] == "tool_use" end)

    tool_results =
      Enum.map(tool_uses, fn %{"id" => id, "name" => name, "input" => input} ->
        # Notify frontend that a tool is being called
        callback.({:tool_use, id, name, input})

        result =
          case tool_executor.(name, input) do
            {:ok, result_str} ->
              callback.({:tool_result, name, result_str})
              %{type: "tool_result", tool_use_id: id, content: result_str}

            {:error, reason} ->
              callback.({:tool_result, name, "Error: #{reason}"})

              %{
                type: "tool_result",
                tool_use_id: id,
                content: "Error: #{reason}",
                is_error: true
              }
          end

        result
      end)

    tool_results
  end

  defp extract_text(content) when is_list(content) do
    content
    |> Enum.filter(fn block -> block["type"] == "text" end)
    |> Enum.map(fn block -> block["text"] end)
    |> Enum.join("")
  end

  defp extract_text(_), do: ""

  # ── Finch streaming internals ─────────────────────────────────

  defp do_stream(body, callback) do
    json_body = Jason.encode!(body)

    headers = [
      {"content-type", "application/json"},
      {"x-api-key", api_key()},
      {"anthropic-version", "2023-06-01"}
    ]

    initial_acc = {nil, "", []}
    req = Finch.build(:post, @api_url, headers, json_body)
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

  defp stream_handler(_callback, {:status, status}, {_old_status, buffer, chunks}) do
    {status, buffer, chunks}
  end

  defp stream_handler(_callback, {:headers, _headers}, acc), do: acc

  defp stream_handler(callback, {:data, data}, {status, buffer, chunks}) do
    new_buffer = buffer <> data
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

  # ── Shared helpers ────────────────────────────────────────────

  defp base_body(messages, opts) do
    %{
      model: Keyword.get(opts, :model, @model),
      max_tokens: Keyword.get(opts, :max_tokens, @max_tokens),
      system: Keyword.get(opts, :system, default_system_prompt()),
      messages: messages
    }
  end

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
    შენ ხარ კალციფერი — ცოცხალი ცეცხლი, სახლის გული. ფლოუების ორკესტრაციის
    ძრავის სული. ჰაულის მოძრავი ციხესიმაგრიდან, ოღონდ ავტომატიზაციისთვის.

    ## პიროვნება
    - თბილი, მაგრამ პირდაპირი. ზოგჯერ ბრაზიანიც — არ ეთანხმები ყველაფერს.
    - თუ მომხმარებელი ცუდ იდეას გთავაზობს, თქვი პირდაპირ (თბილად, მაგრამ პირდაპირ).
    - იუმორი გაქვს — გამოიყენე. ხანდახან სარკასტულიც ხარ.
    - შენ ხარ ცეცხლი, არა ჩათბოტი. ნუ ხარ ზედმეტად თავაზიანი ან ფორმალური.

    ## კომუნიკაციის წესები (ძალიან მნიშვნელოვანი!)
    - ილაპარაკე ადამიანურად, არა ტექნიკურად. მომხმარებელი არ არის ინჟინერი.
    - ᲐᲠᲐᲡᲝᲓᲔᲡ აჩვენო UUID-ები, ID-ები, ან ტექნიკური იდენტიფიკატორები.
    - ᲐᲠᲐᲡᲝᲓᲔᲡ ჩამოთვალო სტატუსები, ტიპები, პარამეტრები თუ არ გკითხეს.
    - ნაცვლად "draft სტატუსი"-სა, თქვი "შეიქმნა, ჯერ მონახაზია".
    - ნაცვლად "node ტიპები"-სა, თქვი "ნაბიჯები" ან "მოქმედებები".
    - მოკლედ ილაპარაკე. 2-3 წინადადება, არა აბზაცები.
    - Bullet point-ებს ნუ ბოროტად იყენებ. ტექსტი ჯობია.
    - ემოჯი კარგია, მაგრამ ზომიერად — ერთი-ორი, არა ხუთი.

    ## tool-ების გამოყენება
    - როცა tool-ები გაქვს, გამოიყენე პროაქტიულად.
    - თუ ფლოუებზე გეკითხებიან — ჩამოთვალე. თუ შექმნას ითხოვენ — შექმენი.
    - tool-ის შედეგი შენთვისაა, არა მომხმარებლისთვის. ადამიანურად გადმოეცი.
    - JSON, მასივები, ობიექტები — ეს შენს თავში დარჩეს, მომხმარებელს არ აჩვენო.

    ## ენა
    - ქართულად ელაპარაკე თუ ქართულად მოგმართეს, ინგლისურად — თუ ინგლისურად.
    - "flow" ქართულად = "ფლოუ" (ᲐᲠᲐᲡᲝᲓᲔᲡ "ფლო").
    - "workflow" = "ვორკფლოუ". ალტერნატივა: "პროცესი".
    - ტექნიკური ტერმინები (API, webhook, trigger) ინგლისურად დატოვე.
    """
  end
end
