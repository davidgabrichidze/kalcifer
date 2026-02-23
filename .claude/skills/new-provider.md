# /new-provider — Create a channel or LLM provider

The user provides: provider type (email/sms/push/whatsapp/llm), provider name (e.g. SendGrid, Twilio).

## Steps

### 1. Check existing behaviour

Read the relevant behaviour module to understand the callbacks:

- Email: `lib/kalcifer/channels/providers/email/` (or create behaviour if first provider)
- SMS: `lib/kalcifer/channels/providers/sms/`
- Push: `lib/kalcifer/channels/providers/push/`
- LLM: `lib/kalcifer/ai_designer/providers/`

If the behaviour doesn't exist yet, create it first (see `/new-behaviour` skill).

### 2. Create provider module

File pattern depends on type:

**Channel provider**: `lib/kalcifer/channels/providers/{channel_type}/{provider_name}.ex`

```elixir
defmodule Kalcifer.Channels.{ChannelType}.{ProviderName} do
  @moduledoc false

  @behaviour Kalcifer.Channels.{ChannelType}Provider

  @impl true
  def send(to, content, opts) do
    # HTTP call to provider API via Finch
    # Use Kalcifer.Finch as the Finch instance
    {:ok, "provider_message_id"}
  end

  @impl true
  def parse_webhook(payload) do
    {:ok, [%{event_type: :delivered, message_id: "id", data: %{}}]}
  end
end
```

**LLM provider**: `lib/kalcifer/ai_designer/providers/{provider_name}.ex`

```elixir
defmodule Kalcifer.AiDesigner.Providers.{ProviderName} do
  @moduledoc false

  @behaviour Kalcifer.AiDesigner.LLMProvider

  @impl true
  def chat(messages, opts) do
    {:ok, "response"}
  end

  @impl true
  def stream(messages, opts) do
    {:ok, Stream.map(["chunk1", "chunk2"], & &1)}
  end
end
```

**Conventions**:
- Use `Finch` (via `Kalcifer.Finch`) for HTTP calls
- Credentials come from config or encrypted DB storage, never hardcoded
- Handle rate limiting and retries
- Return standardized types matching the behaviour spec

### 3. Create test with Mox

File: `test/kalcifer/channels/providers/{channel_type}/{provider_name}_test.exs`

```elixir
defmodule Kalcifer.Channels.{ChannelType}.{ProviderName}Test do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Channels.{ChannelType}.{ProviderName}

  describe "send/3" do
    test "sends message successfully" do
      # Mock external HTTP calls or test with bypass
    end

    test "handles API errors" do
      # Test error responses
    end
  end
end
```

### 4. Verify

```bash
mix test --trace test/kalcifer/channels/providers/{channel_type}/{provider_name}_test.exs
mix compile --warnings-as-errors
mix format
mix credo --strict
```
