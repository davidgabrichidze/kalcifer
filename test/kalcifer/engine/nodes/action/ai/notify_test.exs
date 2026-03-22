defmodule Kalcifer.Engine.Nodes.Action.AI.NotifyTest do
  use ExUnit.Case, async: true

  import Mox

  alias Kalcifer.Engine.Nodes.Action.AI.Notify

  setup :verify_on_exit!

  setup do
    Application.put_env(:kalcifer, :ai_client, Kalcifer.AI.MockClient)
    on_exit(fn -> Application.delete_env(:kalcifer, :ai_client) end)
    :ok
  end

  describe "category/0" do
    test "returns :action" do
      assert Notify.category() == :action
    end
  end

  describe "config_schema/0" do
    test "defines message, summarize, and channel" do
      schema = Notify.config_schema()
      assert schema["message"]["type"] == "string"
      assert schema["summarize"]["default"] == false
      assert schema["channel"]["default"] == "chat"
      assert "slack" in schema["channel"]["enum"]
    end
  end

  describe "execute/2 — dry run" do
    test "returns dry run message without broadcasting" do
      config = %{"message" => "Campaign done!", "channel" => "slack"}
      context = %{"_dry_run" => true, "_tenant_id" => "t1", "_instance_id" => "i1"}

      assert {:completed, result} = Notify.execute(config, context)
      assert result.message =~ "dry run"
      assert result.message =~ "Campaign done!"
      assert result.notified == true
    end
  end

  describe "execute/2 — static message" do
    test "sends static message via PubSub" do
      tenant_id = "tenant_#{System.unique_integer([:positive])}"

      # Subscribe to receive the broadcast
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "operator:#{tenant_id}")

      config = %{"message" => "ფლოუ დასრულდა წარმატებით!", "channel" => "chat"}

      context = %{
        "_tenant_id" => tenant_id,
        "_instance_id" => "inst_123"
      }

      assert {:completed, result} = Notify.execute(config, context)
      assert result.notified == true
      assert result.message == "ფლოუ დასრულდა წარმატებით!"
      assert result.channel == "chat"
      assert result.instance_id == "inst_123"

      # Verify PubSub broadcast was received
      assert_receive {:ai_notification, notification}
      assert notification.message == "ფლოუ დასრულდა წარმატებით!"
      assert notification.channel == "chat"
      assert notification.instance_id == "inst_123"
    end
  end

  describe "execute/2 — template interpolation" do
    test "interpolates {{key}} from accumulated context" do
      tenant_id = "tenant_#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "operator:#{tenant_id}")

      config = %{"message" => "მომხმარებელმა {{name}} დაასრულა ფლოუ"}

      context = %{
        "_tenant_id" => tenant_id,
        "_instance_id" => "i1",
        "accumulated" => %{"name" => "გიორგი"}
      }

      assert {:completed, result} = Notify.execute(config, context)
      assert result.message == "მომხმარებელმა გიორგი დაასრულა ფლოუ"

      assert_receive {:ai_notification, notification}
      assert notification.message =~ "გიორგი"
    end

    test "interpolates from nested node results" do
      tenant_id = "tenant_#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "operator:#{tenant_id}")

      config = %{"message" => "Score: {{score}}"}

      context = %{
        "_tenant_id" => tenant_id,
        "_instance_id" => "i1",
        "accumulated" => %{"scoring_node" => %{"score" => "85"}}
      }

      assert {:completed, result} = Notify.execute(config, context)
      assert result.message == "Score: 85"
    end
  end

  describe "execute/2 — AI summarize" do
    test "calls AI to summarize accumulated context" do
      tenant_id = "tenant_#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "operator:#{tenant_id}")

      expect(Kalcifer.AI.MockClient, :chat, fn messages, _opts ->
        content = hd(messages).content
        assert content =~ "Summarize"
        assert content =~ "email_sent"
        {:ok, "კამპანია წარმატებით დასრულდა, 3 ემეილი გაიგზავნა."}
      end)

      config = %{"summarize" => true, "channel" => "slack"}

      context = %{
        "_tenant_id" => tenant_id,
        "_instance_id" => "i1",
        "accumulated" => %{"step_1" => %{"email_sent" => true, "count" => 3}}
      }

      assert {:completed, result} = Notify.execute(config, context)
      assert result.message =~ "კამპანია წარმატებით"
      assert result.channel == "slack"

      assert_receive {:ai_notification, notification}
      assert notification.channel == "slack"
    end

    test "falls back gracefully on AI error" do
      tenant_id = "tenant_#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "operator:#{tenant_id}")

      expect(Kalcifer.AI.MockClient, :chat, fn _messages, _opts ->
        {:error, :timeout}
      end)

      config = %{"summarize" => true}

      context = %{
        "_tenant_id" => tenant_id,
        "_instance_id" => "i1",
        "accumulated" => %{}
      }

      assert {:completed, result} = Notify.execute(config, context)
      assert result.message =~ "ფლოუ დასრულდა"
      assert result.notified == true
    end
  end

  describe "execute/2 — default message" do
    test "uses default Georgian message when no config message" do
      tenant_id = "tenant_#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "operator:#{tenant_id}")

      config = %{}
      context = %{"_tenant_id" => tenant_id, "_instance_id" => "i1"}

      assert {:completed, result} = Notify.execute(config, context)
      assert result.message == "ფლოუ დასრულდა."
    end
  end

  describe "execute/2 — channel defaults" do
    test "defaults to chat channel" do
      tenant_id = "tenant_#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Kalcifer.PubSub, "operator:#{tenant_id}")

      config = %{"message" => "Done"}
      context = %{"_tenant_id" => tenant_id, "_instance_id" => "i1"}

      assert {:completed, result} = Notify.execute(config, context)
      assert result.channel == "chat"
    end
  end
end
