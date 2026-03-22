defmodule KalciferWeb.ChatController do
  use KalciferWeb, :controller

  alias Kalcifer.AI.Client

  @doc """
  POST /api/v1/chat

  Accepts `{"messages": [{"role": "user", "content": "..."}]}`.
  Streams the AI response back as Server-Sent Events.
  """
  def create(conn, %{"messages" => messages}) do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    api_messages =
      Enum.map(messages, fn msg ->
        %{role: msg["role"], content: msg["content"]}
      end)

    callback = fn
      {:text_delta, text} ->
        chunk_sse(conn, "delta", %{text: text})

      {:done, full_text} ->
        chunk_sse(conn, "done", %{text: full_text})

      {:error, reason} ->
        chunk_sse(conn, "error", %{message: inspect(reason)})
    end

    case Client.stream(api_messages, callback) do
      {:ok, _full_text} ->
        conn

      {:error, reason} ->
        chunk_sse(conn, "error", %{message: inspect(reason)})
        conn
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "messages parameter required"})
  end

  defp chunk_sse(conn, event, data) do
    payload = "event: #{event}\ndata: #{Jason.encode!(data)}\n\n"

    case chunk(conn, payload) do
      {:ok, _conn} -> conn
      {:error, :closed} -> conn
    end
  end
end
