defmodule Kalcifer.Engine.Nodes.Action.AI.ThinkTest do
  use ExUnit.Case, async: true

  import Mox

  alias Kalcifer.Engine.Nodes.Action.AI.Think

  setup :verify_on_exit!

  setup do
    # Use mock client for all tests in this module
    Application.put_env(:kalcifer, :ai_client, Kalcifer.AI.MockClient)
    on_exit(fn -> Application.delete_env(:kalcifer, :ai_client) end)
    :ok
  end

  describe "category/0" do
    test "returns :action" do
      assert Think.category() == :action
    end
  end

  describe "config_schema/0" do
    test "defines prompt, system, and include_context" do
      schema = Think.config_schema()
      assert schema["prompt"]["required"] == true
      assert schema["system"]["type"] == "string"
      assert schema["include_context"]["default"] == true
    end
  end

  describe "validate/1" do
    test "accepts valid config" do
      assert :ok = Think.validate(%{"prompt" => "Analyze this"})
    end

    test "rejects missing prompt" do
      assert {:error, _} = Think.validate(%{})
    end

    test "rejects empty prompt" do
      assert {:error, _} = Think.validate(%{"prompt" => ""})
    end
  end

  describe "execute/2 — dry run" do
    test "skips AI call and returns placeholder" do
      config = %{"prompt" => "What should we do?"}
      context = %{"_dry_run" => true}

      assert {:completed, result} = Think.execute(config, context)
      assert result.dry_run == true
      assert result.would_think_about == "What should we do?"
      assert result.response =~ "dry run"
    end
  end

  describe "execute/2 — real call" do
    test "sends prompt to AI and returns response" do
      expect(Kalcifer.AI.MockClient, :chat, fn messages, _opts ->
        assert length(messages) == 1
        assert hd(messages).role == "user"
        assert hd(messages).content =~ "Analyze user behavior"
        {:ok, "Users show high engagement on Tuesdays."}
      end)

      config = %{"prompt" => "Analyze user behavior"}
      context = %{}

      assert {:completed, result} = Think.execute(config, context)
      assert result.response == "Users show high engagement on Tuesdays."
      assert result.prompt == "Analyze user behavior"
    end

    test "includes accumulated context when include_context is true" do
      expect(Kalcifer.AI.MockClient, :chat, fn messages, _opts ->
        content = hd(messages).content
        assert content =~ "step_1"
        assert content =~ "email_sent"
        {:ok, "Noted."}
      end)

      config = %{"prompt" => "Summarize", "include_context" => true}
      context = %{"accumulated" => %{"step_1" => %{"email_sent" => true}}}

      assert {:completed, _} = Think.execute(config, context)
    end

    test "excludes context when include_context is false" do
      expect(Kalcifer.AI.MockClient, :chat, fn messages, _opts ->
        content = hd(messages).content
        refute content =~ "accumulated"
        refute content =~ "Context:"
        {:ok, "Done."}
      end)

      config = %{"prompt" => "Just think", "include_context" => false}
      context = %{"accumulated" => %{"step_1" => %{"data" => "secret"}}}

      assert {:completed, _} = Think.execute(config, context)
    end

    test "passes custom system prompt" do
      expect(Kalcifer.AI.MockClient, :chat, fn _messages, opts ->
        assert Keyword.get(opts, :system) == "You are a marketing expert."
        {:ok, "Here's my analysis."}
      end)

      config = %{"prompt" => "Analyze", "system" => "You are a marketing expert."}
      context = %{}

      assert {:completed, _} = Think.execute(config, context)
    end

    test "returns failure on API error" do
      expect(Kalcifer.AI.MockClient, :chat, fn _messages, _opts ->
        {:error, :timeout}
      end)

      config = %{"prompt" => "Think about this"}
      context = %{}

      assert {:failed, reason} = Think.execute(config, context)
      assert reason.reason == :ai_error
    end
  end
end
