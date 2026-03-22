defmodule Kalcifer.Engine.Nodes.Action.AI.DecideTest do
  use ExUnit.Case, async: true

  import Mox

  alias Kalcifer.Engine.Nodes.Action.AI.Decide

  setup :verify_on_exit!

  setup do
    Application.put_env(:kalcifer, :ai_client, Kalcifer.AI.MockClient)
    on_exit(fn -> Application.delete_env(:kalcifer, :ai_client) end)
    :ok
  end

  describe "category/0" do
    test "returns :condition" do
      assert Decide.category() == :condition
    end
  end

  describe "config_schema/0" do
    test "defines question, branches, and criteria" do
      schema = Decide.config_schema()
      assert schema["question"]["required"] == true
      assert schema["branches"]["required"] == true
      assert schema["criteria"]["type"] == "string"
    end
  end

  describe "validate/1" do
    test "accepts valid config" do
      config = %{"question" => "Approve?", "branches" => ["yes", "no"]}
      assert :ok = Decide.validate(config)
    end

    test "rejects missing question" do
      config = %{"branches" => ["yes", "no"]}
      assert {:error, errors} = Decide.validate(config)
      assert Enum.any?(errors, &(&1 =~ "question"))
    end

    test "rejects fewer than 2 branches" do
      config = %{"question" => "Go?", "branches" => ["yes"]}
      assert {:error, errors} = Decide.validate(config)
      assert Enum.any?(errors, &(&1 =~ "branches"))
    end

    test "rejects missing branches" do
      config = %{"question" => "Go?"}
      assert {:error, errors} = Decide.validate(config)
      assert Enum.any?(errors, &(&1 =~ "branches"))
    end
  end

  describe "execute/2 — dry run" do
    test "picks first branch without AI call" do
      config = %{
        "question" => "Should we send?",
        "branches" => ["send", "skip", "escalate"]
      }

      context = %{"_dry_run" => true}

      assert {:branched, "send", result} = Decide.execute(config, context)
      assert result.dry_run == true
      assert result.chose == "send"
    end
  end

  describe "execute/2 — real call" do
    test "picks the branch returned by AI" do
      expect(Kalcifer.AI.MockClient, :chat, fn messages, _opts ->
        content = hd(messages).content
        assert content =~ "approve, reject, escalate"
        assert content =~ "Is the order valid?"
        {:ok, "approve"}
      end)

      config = %{
        "question" => "Is the order valid?",
        "branches" => ["approve", "reject", "escalate"]
      }

      context = %{}

      assert {:branched, "approve", result} = Decide.execute(config, context)
      assert result.chose == "approve"
      assert result.question == "Is the order valid?"
    end

    test "falls back to first branch on unrecognized response" do
      expect(Kalcifer.AI.MockClient, :chat, fn _messages, _opts ->
        {:ok, "I think we should probably approve this request"}
      end)

      config = %{
        "question" => "Approve?",
        "branches" => ["approve", "reject"]
      }

      context = %{}

      assert {:branched, "approve", _result} = Decide.execute(config, context)
    end

    test "handles case-insensitive matching" do
      expect(Kalcifer.AI.MockClient, :chat, fn _messages, _opts ->
        {:ok, "REJECT"}
      end)

      config = %{
        "question" => "Valid?",
        "branches" => ["approve", "reject"]
      }

      context = %{}

      assert {:branched, "reject", _result} = Decide.execute(config, context)
    end

    test "includes accumulated context in prompt" do
      expect(Kalcifer.AI.MockClient, :chat, fn messages, _opts ->
        content = hd(messages).content
        assert content =~ "score_node"
        {:ok, "approve"}
      end)

      config = %{
        "question" => "Based on score, approve?",
        "branches" => ["approve", "reject"]
      }

      context = %{"accumulated" => %{"score_node" => %{"score" => 85}}}

      assert {:branched, "approve", _} = Decide.execute(config, context)
    end

    test "returns failure on API error" do
      expect(Kalcifer.AI.MockClient, :chat, fn _messages, _opts ->
        {:error, {:api_error, 500, %{}}}
      end)

      config = %{
        "question" => "Approve?",
        "branches" => ["yes", "no"]
      }

      context = %{}

      assert {:failed, reason} = Decide.execute(config, context)
      assert reason.reason == :ai_decision_error
    end
  end
end
