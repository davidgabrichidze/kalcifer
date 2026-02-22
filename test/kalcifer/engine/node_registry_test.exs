defmodule Kalcifer.Engine.NodeRegistryTest do
  use ExUnit.Case, async: false

  alias Kalcifer.Engine.NodeRegistry

  describe "lookup/1" do
    test "returns module for registered node type" do
      assert {:ok, Kalcifer.Engine.Nodes.Entry.EventEntry} = NodeRegistry.lookup("event_entry")
    end

    test "returns :error for unknown node type" do
      assert :error = NodeRegistry.lookup("nonexistent_type")
    end
  end

  describe "list_all/0" do
    test "includes at least 19 built-in node types" do
      all = NodeRegistry.list_all()
      assert length(all) >= 19
    end

    test "includes all entry nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["event_entry"] == Kalcifer.Engine.Nodes.Entry.EventEntry
      assert all["segment_entry"] == Kalcifer.Engine.Nodes.Entry.SegmentEntry
      assert all["webhook_entry"] == Kalcifer.Engine.Nodes.Entry.WebhookEntry
    end

    test "includes all channel nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["send_email"] == Kalcifer.Engine.Nodes.Channel.SendEmail
      assert all["send_sms"] == Kalcifer.Engine.Nodes.Channel.SendSms
      assert all["send_push"] == Kalcifer.Engine.Nodes.Channel.SendPush
      assert all["send_whatsapp"] == Kalcifer.Engine.Nodes.Channel.SendWhatsapp
      assert all["call_webhook"] == Kalcifer.Engine.Nodes.Channel.CallWebhook
    end

    test "includes all logic nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["condition"] == Kalcifer.Engine.Nodes.Logic.Condition
      assert all["ab_split"] == Kalcifer.Engine.Nodes.Logic.AbSplit
      assert all["wait"] == Kalcifer.Engine.Nodes.Logic.Wait
      assert all["wait_until"] == Kalcifer.Engine.Nodes.Logic.WaitUntil
      assert all["wait_for_event"] == Kalcifer.Engine.Nodes.Logic.WaitForEvent
      assert all["frequency_cap"] == Kalcifer.Engine.Nodes.Logic.FrequencyCapNode
    end

    test "includes all data and exit nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["update_profile"] == Kalcifer.Engine.Nodes.Data.UpdateProfile
      assert all["add_tag"] == Kalcifer.Engine.Nodes.Data.AddTag
      assert all["custom_code"] == Kalcifer.Engine.Nodes.Data.CustomCode
      assert all["journey_exit"] == Kalcifer.Engine.Nodes.Exit.JourneyExit
      assert all["goal_reached"] == Kalcifer.Engine.Nodes.Exit.GoalReached
    end
  end

  describe "register/2" do
    test "registers a custom node type" do
      NodeRegistry.register("test_custom", Kalcifer.Engine.Nodes.Exit.JourneyExit)
      assert {:ok, Kalcifer.Engine.Nodes.Exit.JourneyExit} = NodeRegistry.lookup("test_custom")
    end
  end
end
