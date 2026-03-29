defmodule Kalcifer.Engine.Nodes.Action.AI.AgentTest do
  use ExUnit.Case, async: true

  import Mox

  alias Kalcifer.Engine.Nodes.Action.AI.Agent

  setup :verify_on_exit!

  setup do
    Application.put_env(:kalcifer, :ai_client, Kalcifer.AI.MockClient)
    on_exit(fn -> Application.delete_env(:kalcifer, :ai_client) end)
    :ok
  end

  describe "category/0" do
    test "returns :action" do
      assert Agent.category() == :action
    end
  end

  describe "config_schema/0" do
    test "defines prompt, system, model, tools, max_rounds" do
      schema = Agent.config_schema()
      assert schema["prompt"]["required"] == true
      assert schema["system"]["type"] == "string"
      assert schema["model"]["type"] == "string"
      assert schema["tools"]["type"] == "array"
      assert schema["max_rounds"]["default"] == 20
    end
  end

  describe "validate/1" do
    test "accepts valid config" do
      assert :ok = Agent.validate(%{"prompt" => "Build a flow"})
    end

    test "rejects missing prompt" do
      assert {:error, _} = Agent.validate(%{})
    end

    test "rejects empty prompt" do
      assert {:error, _} = Agent.validate(%{"prompt" => ""})
    end
  end

  describe "execute/2 — dry run" do
    test "skips agent loop and returns placeholder" do
      config = %{"prompt" => "Build me an onboarding flow"}
      context = %{"_dry_run" => true}

      assert {:completed, result} = Agent.execute(config, context)
      assert result.dry_run == true
      assert result.would_execute == "Build me an onboarding flow"
      assert result.response =~ "dry run"
    end
  end

  describe "execute/2 — real call" do
    test "runs chat_with_tools and returns response" do
      expect(Kalcifer.AI.MockClient, :chat_with_tools, fn _messages,
                                                          _tools,
                                                          _executor,
                                                          callback,
                                                          _opts ->
        # Simulate streaming
        callback.({:text_delta, "Hello "})
        callback.({:text_delta, "there!"})
        callback.({:done, "Hello there!"})
        {:ok, "Hello there!"}
      end)

      config = %{"prompt" => "Say hello"}

      context = %{
        "_instance_id" => "test-instance-123",
        "_tenant_id" => "test-tenant-456",
        "_conversation_id" => "test-conv-789"
      }

      assert {:completed, result} = Agent.execute(config, context)
      assert result.response == "Hello there!"
      assert result.tool_calls == []
      assert result.rounds == 0
    end

    test "tracks tool calls in result" do
      expect(Kalcifer.AI.MockClient, :chat_with_tools, fn _messages,
                                                          _tools,
                                                          _executor,
                                                          callback,
                                                          _opts ->
        # Simulate tool call
        callback.({:tool_use, "t1", "create_flow", %{"name" => "Test"}})
        callback.({:tool_result, "create_flow", "{\"id\": \"abc\"}"})
        callback.({:text_delta, "Done!"})
        callback.({:done, "Done!"})
        {:ok, "Done!"}
      end)

      config = %{"prompt" => "Create a flow"}

      context = %{
        "_instance_id" => "test-instance-123",
        "_tenant_id" => "test-tenant-456",
        "_conversation_id" => "test-conv-789"
      }

      assert {:completed, result} = Agent.execute(config, context)
      assert result.response == "Done!"
      assert length(result.tool_calls) == 1
      assert hd(result.tool_calls).tool == "create_flow"
    end

    test "returns failure on API error" do
      expect(Kalcifer.AI.MockClient, :chat_with_tools, fn _messages,
                                                          _tools,
                                                          _executor,
                                                          _callback,
                                                          _opts ->
        {:error, {:api_error, 500, "Internal Server Error"}}
      end)

      config = %{"prompt" => "Do something"}

      context = %{
        "_instance_id" => "test-instance-123",
        "_tenant_id" => "test-tenant-456",
        "_conversation_id" => "test-conv-789"
      }

      assert {:failed, result} = Agent.execute(config, context)
      assert result.reason == :agent_error
    end

    test "uses messages from context when available" do
      expect(Kalcifer.AI.MockClient, :chat_with_tools, fn messages,
                                                          _tools,
                                                          _executor,
                                                          callback,
                                                          _opts ->
        # Verify messages from context are used
        assert length(messages) == 2
        assert hd(messages).role == "user"
        assert hd(messages).content == "Previous message"
        callback.({:done, "OK"})
        {:ok, "OK"}
      end)

      config = %{"prompt" => "{{_initial_message}}"}

      context = %{
        "_instance_id" => "test-instance-123",
        "_tenant_id" => "test-tenant-456",
        "_conversation_id" => "test-conv-789",
        "_messages" => [
          %{role: "user", content: "Previous message"},
          %{role: "assistant", content: "I see"}
        ]
      }

      assert {:completed, _} = Agent.execute(config, context)
    end

    test "uses system prompt from context as fallback" do
      expect(Kalcifer.AI.MockClient, :chat_with_tools, fn _messages,
                                                          _tools,
                                                          _executor,
                                                          callback,
                                                          opts ->
        assert Keyword.get(opts, :system) == "You are a helpful assistant"
        callback.({:done, "OK"})
        {:ok, "OK"}
      end)

      config = %{"prompt" => "Hello"}

      context = %{
        "_instance_id" => "test-instance-123",
        "_tenant_id" => "test-tenant-456",
        "_conversation_id" => "test-conv-789",
        "_system_prompt" => "You are a helpful assistant"
      }

      assert {:completed, _} = Agent.execute(config, context)
    end

    test "config system prompt overrides context" do
      expect(Kalcifer.AI.MockClient, :chat_with_tools, fn _messages,
                                                          _tools,
                                                          _executor,
                                                          callback,
                                                          opts ->
        assert Keyword.get(opts, :system) == "I am Kalcifer"
        callback.({:done, "OK"})
        {:ok, "OK"}
      end)

      config = %{"prompt" => "Hello", "system" => "I am Kalcifer"}

      context = %{
        "_instance_id" => "test-instance-123",
        "_tenant_id" => "test-tenant-456",
        "_conversation_id" => "test-conv-789",
        "_system_prompt" => "You are a helpful assistant"
      }

      assert {:completed, _} = Agent.execute(config, context)
    end

    test "broadcasts text deltas via PubSub" do
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "instance:pubsub-test-instance")

      expect(Kalcifer.AI.MockClient, :chat_with_tools, fn _messages,
                                                          _tools,
                                                          _executor,
                                                          callback,
                                                          _opts ->
        callback.({:text_delta, "Hello"})
        callback.({:done, "Hello"})
        {:ok, "Hello"}
      end)

      config = %{"prompt" => "Say hello"}

      context = %{
        "_instance_id" => "pubsub-test-instance",
        "_tenant_id" => "test-tenant",
        "_conversation_id" => "test-conv"
      }

      assert {:completed, _} = Agent.execute(config, context)

      assert_receive %{type: "agent_text_delta", payload: %{text: "Hello"}}
      assert_receive %{type: "agent_done", payload: %{text: "Hello"}}
    end

    test "broadcasts tool events via PubSub" do
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "instance:pubsub-tool-test")

      expect(Kalcifer.AI.MockClient, :chat_with_tools, fn _messages,
                                                          _tools,
                                                          _executor,
                                                          callback,
                                                          _opts ->
        callback.({:tool_use, "t1", "list_flows", %{}})
        callback.({:tool_result, "list_flows", "[]"})
        callback.({:done, "No flows"})
        {:ok, "No flows"}
      end)

      config = %{"prompt" => "List flows"}

      context = %{
        "_instance_id" => "pubsub-tool-test",
        "_tenant_id" => "test-tenant",
        "_conversation_id" => "test-conv"
      }

      assert {:completed, _} = Agent.execute(config, context)

      assert_receive %{type: "agent_tool_start", payload: %{tool: "list_flows"}}
      assert_receive %{type: "agent_tool_done", payload: %{tool: "list_flows", result: "[]"}}
    end
  end
end
