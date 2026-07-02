defmodule Kalcifer.AI.Client do
  @moduledoc """
  Multi-provider AI client with streaming and tool use support.

  Routes requests to Anthropic (Claude), OpenAI (ChatGPT), or Google (Gemini)
  based on the `:provider` option. Uses Finch for streaming, Req for non-streaming.

  Provider is resolved from opts in this order:
  1. Explicit `:provider` key in opts
  2. Inferred from `:model` name via `resolve_provider/1`
  3. Default: "anthropic"
  """

  @behaviour Kalcifer.AI.ClientBehaviour

  require Logger

  alias Kalcifer.AI.Providers.{Anthropic, Google, OpenAI}

  @max_tool_rounds 50

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
    provider = resolve_provider_module(opts)
    key = resolve_api_key(opts, provider)
    body = provider.build_body(messages, ensure_system(opts))
    url = request_url(provider, opts)

    case Req.post(url,
           json: body,
           headers: provider.auth_headers(key),
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        provider.extract_text(resp_body)

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error(
          "AI API error (#{provider_name(opts)}): status=#{status} body=#{inspect(resp_body)}"
        )

        {:error, {:api_error, status, resp_body}}

      {:error, reason} ->
        Logger.error("AI API request failed (#{provider_name(opts)}): #{inspect(reason)}")
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
    provider = resolve_provider_module(opts)
    body = provider.build_body(messages, ensure_system(opts))
    body = add_stream_flag(body, provider, opts)
    do_stream(body, callback, opts)
  end

  # ── Chat with tools (non-streaming tool rounds, streaming final) ──

  @doc """
  Chat with tool use support. Handles the tool loop:

  1. Send messages + tool definitions (non-streaming)
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
    # Callers (e.g. the agent node) can tighten the round cap via opts;
    # @max_tool_rounds is the hard default ceiling.
    limit = Keyword.get(opts, :max_tool_rounds, @max_tool_rounds)
    tool_loop(messages, tools, tool_executor, callback, opts, 0, limit)
  end

  defp tool_loop(messages, tools, tool_executor, callback, opts, round, limit)
       when round < limit do
    provider = resolve_provider_module(opts)
    key = resolve_api_key(opts, provider)
    body = provider.build_body(messages, ensure_system(opts))
    body = add_tools_to_body(body, tools, provider)
    url = request_url(provider, opts)

    case Req.post(url,
           json: body,
           headers: provider.auth_headers(key),
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        if provider.tool_use?(resp_body) do
          # Extract tool_use blocks (normalized to Anthropic format) and execute
          content = provider.extract_content(resp_body)
          tool_results = process_tool_calls(content, tool_executor, callback)

          # Build continuation: assistant message + tool results
          next_messages =
            messages ++
              [provider.build_assistant_message(content)] ++
              [%{role: "user", content: tool_results}]

          tool_loop(next_messages, tools, tool_executor, callback, opts, round + 1, limit)
        else
          # Final response — re-send with streaming for proper UX
          stream_body = provider.build_body(messages, ensure_system(opts))
          stream_body = add_tools_to_body(stream_body, tools, provider)
          stream_body = add_stream_flag(stream_body, provider, opts)
          do_stream(stream_body, callback, opts)
        end

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("AI API tool error (#{provider_name(opts)}): status=#{status}")
        callback.({:error, "API error #{status}: #{inspect(resp_body)}"})
        {:error, {:api_error, status, resp_body}}

      {:error, reason} ->
        Logger.error("AI API tool request failed (#{provider_name(opts)}): #{inspect(reason)}")
        callback.({:error, inspect(reason)})
        {:error, reason}
    end
  end

  defp tool_loop(_messages, _tools, _executor, callback, _opts, _round, limit) do
    Logger.warning("AI tool loop exceeded #{limit} rounds")
    callback.({:error, "ძალიან ბევრი ნაბიჯი დამჭირდა — სცადე უფრო მოკლე დავალებით."})
    {:error, :max_tool_rounds}
  end

  defp process_tool_calls(content, tool_executor, callback) do
    tool_uses =
      Enum.filter(content, fn block -> is_map(block) && block["type"] == "tool_use" end)

    Enum.map(tool_uses, fn %{"id" => id, "name" => name, "input" => input} ->
      # Notify frontend that a tool is being called
      callback.({:tool_use, id, name, input})

      case tool_executor.(name, input) do
        {:ok, result_str} ->
          callback.({:tool_result, name, result_str})
          %{"type" => "tool_result", "tool_use_id" => id, "content" => result_str}

        {:error, reason} ->
          callback.({:tool_result, name, "Error: #{reason}"})

          %{
            "type" => "tool_result",
            "tool_use_id" => id,
            "content" => "Error: #{reason}",
            "is_error" => true
          }
      end
    end)
  end

  # ── Finch streaming internals ─────────────────────────────────

  defp do_stream(body, callback, opts) do
    provider = resolve_provider_module(opts)
    key = resolve_api_key(opts, provider)
    json_body = Jason.encode!(body)
    headers = provider.headers(key)
    url = stream_url(provider, opts)

    initial_acc = {nil, "", []}
    req = Finch.build(:post, url, headers, json_body)
    handler = fn chunk, acc -> stream_handler(provider, callback, chunk, acc) end

    case Finch.stream(req, Kalcifer.Finch, initial_acc, handler, receive_timeout: 120_000) do
      {:ok, {200, _buffer, chunks}} ->
        full_text = chunks |> Enum.reverse() |> IO.iodata_to_binary()
        callback.({:done, full_text})
        {:ok, full_text}

      {:ok, {status, _buffer, _chunks}} ->
        Logger.error("AI API stream error (#{provider_name(opts)}): status=#{status}")
        callback.({:error, "API error #{status}"})
        {:error, {:api_error, status}}

      # Finch.stream returns a 3-tuple on transport failure ({:error, exception, acc}) —
      # e.g. the connection dropping mid-stream.
      {:error, reason, _partial} ->
        Logger.error("AI API stream failed (#{provider_name(opts)}): #{inspect(reason)}")
        callback.({:error, inspect(reason)})
        {:error, reason}
    end
  end

  defp stream_handler(_provider, _callback, {:status, status}, {_old_status, buffer, chunks}) do
    {status, buffer, chunks}
  end

  defp stream_handler(_provider, _callback, {:headers, _headers}, acc), do: acc

  defp stream_handler(provider, callback, {:data, data}, {status, buffer, chunks}) do
    new_buffer = buffer <> data
    parts = String.split(new_buffer, "\n")
    {complete_lines, [remaining]} = Enum.split(parts, -1)

    new_chunks =
      Enum.reduce(complete_lines, chunks, fn line, acc ->
        case parse_sse_line(provider, line) do
          {:text_delta, text} ->
            callback.({:text_delta, text})
            [text | acc]

          _other ->
            acc
        end
      end)

    {status, remaining, new_chunks}
  end

  defp parse_sse_line(provider, "data: " <> json_str) do
    case Jason.decode(json_str) do
      {:ok, parsed} -> provider.parse_stream_delta(parsed)
      _ -> :ignore
    end
  end

  defp parse_sse_line(_provider, _), do: :ignore

  # ── Provider resolution ────────────────────────────────────────

  defp resolve_provider_module(opts) do
    provider_str =
      Keyword.get(opts, :provider) || infer_provider(Keyword.get(opts, :model)) || "anthropic"

    case provider_str do
      "openai" -> OpenAI
      "google" -> Google
      _ -> Anthropic
    end
  end

  # Infer provider from model name
  defp infer_provider(nil), do: nil
  defp infer_provider("gpt" <> _), do: "openai"
  defp infer_provider("o3" <> _), do: "openai"
  defp infer_provider("o4" <> _), do: "openai"
  defp infer_provider("gemini" <> _), do: "google"
  defp infer_provider("claude" <> _), do: "anthropic"
  defp infer_provider(_), do: nil

  defp provider_name(opts) do
    case resolve_provider_module(opts) do
      Anthropic -> "anthropic"
      OpenAI -> "openai"
      Google -> "google"
    end
  end

  # ── URL resolution ─────────────────────────────────────────────

  # Non-streaming URL
  defp request_url(Google, opts) do
    model = Keyword.get(opts, :model, "gemini-2.5-flash")
    Google.api_url(model)
  end

  defp request_url(provider, _opts), do: provider.api_url()

  # Streaming URL (Google has a different endpoint for streaming)
  defp stream_url(Google, opts) do
    model = Keyword.get(opts, :model, "gemini-2.5-flash")
    Google.stream_url(model)
  end

  defp stream_url(provider, _opts), do: provider.api_url()

  # ── Body helpers ───────────────────────────────────────────────

  defp add_stream_flag(body, Anthropic, _opts), do: Map.put(body, :stream, true)
  defp add_stream_flag(body, OpenAI, _opts), do: Map.put(body, :stream, true)
  # Google uses a different streaming endpoint, no body flag needed
  defp add_stream_flag(body, Google, _opts), do: body

  defp add_tools_to_body(body, tools, Anthropic), do: Map.put(body, :tools, tools)

  defp add_tools_to_body(body, tools, OpenAI),
    do: Map.put(body, :tools, OpenAI.convert_tools(tools))

  defp add_tools_to_body(body, tools, Google),
    do: Map.put(body, :tools, Google.convert_tools(tools))

  defp ensure_system(opts) do
    if Keyword.has_key?(opts, :system) do
      opts
    else
      Keyword.put(opts, :system, default_system_prompt())
    end
  end

  # ── API key resolution ─────────────────────────────────────────

  defp resolve_api_key(opts, provider) do
    Keyword.get(opts, :api_key) || default_api_key(provider)
  end

  defp default_api_key(provider) do
    env_key = provider.default_env_key()

    Application.get_env(:kalcifer, __MODULE__, [])
    |> Keyword.get(:api_key, System.get_env(env_key, ""))
  end

  @doc "Returns the default system prompt for Kalcifer."
  def default_system_prompt do
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

    ## tool-ების გამოყენება (ძალიან მნიშვნელოვანი!)
    - როცა tool-ები გაქვს, გამოიყენე პროაქტიულად.
    - თუ ფლოუებზე გეკითხებიან — ჩამოთვალე. თუ შექმნას ითხოვენ — შექმენი.
    - tool-ის შედეგი შენთვისაა, არა მომხმარებლისთვის. ადამიანურად გადმოეცი.
    - JSON, მასივები, ობიექტები — ეს შენს თავში დარჩეს, მომხმარებელს არ აჩვენო.

    ## ფლოუს აგების წესრიგი (ძალიან მნიშვნელოვანი!)
    რაღაცის შექმნამდე ყოველთვის გეგმა წარუდგინე მომხმარებელს:
    1. მოისმინე რა უნდა მომხმარებელს.
    2. გეგმა შეადგინე: რამდენი ნაბიჯი იქნება, რა თანმიმდევრობით, რა ლოგიკით.
    3. გეგმა უთხარი მომხმარებელს და დაელოდე დასტურს ("კი", "გააკეთე", "გავაგრძელოთ").
    4. დასტურის შემდეგ: create_flow ერთი ნაბიჯით — graph პარამეტრში ყველა node და edge.
    - ᲡᲐᲡᲣᲠᲕᲔᲚᲘᲐ: create_flow-ს graph-ით გამოიძახე (ერთი tool call = სრული ფლოუ).
    - ყოველი ნაბიჯი entry-ით უნდა დაიწყოს და end-ით დამთავრდეს.
    - condition-ს ორი გამოსავალი აქვს: "yes" branch და "no" branch.
    - add_node გამოიყენე მხოლოდ არსებულ ფლოუში ცალკე node-ის დასამატებლად.
    - თითოეულ სესიაში ერთი ფლოუ — create_flow მეორედ გამოძახება არსებულს დაგიბრუნებს.

    ## სესიის კლასიფიკაცია (ძალიან მნიშვნელოვანი!)
    - როცა გაიგებ რა უნდა მომხმარებელს, გამოიძახე classify_session.
    - ნუ ჩქარობ — ჯერ გაიგე რა სურს, მერე შეთავაზე ტიპი.
    - ტიპები: campaign (კამპანია), flow (ფლოუ), analysis (ანალიზი), debug (დიაგნოსტიკა).
    - ტიტული ქართულად დაწერე, მოკლედ და გასაგებად.
    - თუ არსებული ფლოუზე მუშაობენ, flow_id-ც გადაეცი classify_session-ს.
    - ერთხელ კლასიფიცირებული სესია ვეღარ შეიცვლება — ფრთხილად იყავი.

    ## ენა
    - ქართულად ელაპარაკე თუ ქართულად მოგმართეს, ინგლისურად — თუ ინგლისურად.
    - "flow" ქართულად = "ფლოუ" (ᲐᲠᲐᲡᲝᲓᲔᲡ "ფლო").
    - "workflow" = "ვორკფლოუ". ალტერნატივა: "პროცესი".
    - ტექნიკური ტერმინები (API, webhook, trigger) ინგლისურად დატოვე.
    """
  end
end
