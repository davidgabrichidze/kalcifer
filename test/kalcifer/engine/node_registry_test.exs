defmodule Kalcifer.Engine.NodeRegistryTest do
  use ExUnit.Case, async: false

  alias Kalcifer.Engine.NodeRegistry

  describe "lookup/1" do
    test "returns module for registered node type" do
      assert {:ok, Kalcifer.Engine.Nodes.Trigger.EventEntry} =
               NodeRegistry.lookup("event_entry")
    end

    test "returns :error for unknown node type" do
      assert :error = NodeRegistry.lookup("nonexistent_type")
    end
  end

  describe "list_all/0" do
    test "includes at least 23 built-in node types" do
      all = NodeRegistry.list_all()
      assert length(all) >= 23
    end

    test "includes all trigger nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["event_entry"] == Kalcifer.Engine.Nodes.Trigger.EventEntry
      assert all["segment_entry"] == Kalcifer.Engine.Nodes.Trigger.SegmentEntry
      assert all["webhook_entry"] == Kalcifer.Engine.Nodes.Trigger.WebhookEntry
    end

    test "includes all action/channel nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["send_email"] == Kalcifer.Engine.Nodes.Action.Channel.SendEmail
      assert all["send_sms"] == Kalcifer.Engine.Nodes.Action.Channel.SendSms
      assert all["send_push"] == Kalcifer.Engine.Nodes.Action.Channel.SendPush
      assert all["send_whatsapp"] == Kalcifer.Engine.Nodes.Action.Channel.SendWhatsapp
      assert all["call_webhook"] == Kalcifer.Engine.Nodes.Action.Channel.CallWebhook
    end

    test "includes all condition and wait nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["condition"] == Kalcifer.Engine.Nodes.Condition.Condition
      assert all["ab_split"] == Kalcifer.Engine.Nodes.Condition.AbSplit
      assert all["frequency_cap"] == Kalcifer.Engine.Nodes.Condition.FrequencyCap
      assert all["wait"] == Kalcifer.Engine.Nodes.Wait.Wait
      assert all["wait_until"] == Kalcifer.Engine.Nodes.Wait.WaitUntil
      assert all["wait_for_event"] == Kalcifer.Engine.Nodes.Wait.WaitForEvent
    end

    test "includes all action/data and end nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["update_profile"] == Kalcifer.Engine.Nodes.Action.Data.UpdateProfile
      assert all["add_tag"] == Kalcifer.Engine.Nodes.Action.Data.AddTag
      assert all["custom_code"] == Kalcifer.Engine.Nodes.Action.Data.CustomCode
      assert all["exit"] == Kalcifer.Engine.Nodes.End.Exit
      assert all["goal_reached"] == Kalcifer.Engine.Nodes.End.GoalReached
    end
  end

  describe "marketing node types" do
    test "includes all marketing-specific nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["send_in_app"] == Kalcifer.Engine.Nodes.Action.Channel.SendInApp
      assert all["check_segment"] == Kalcifer.Engine.Nodes.Condition.CheckSegment
      assert all["preference_gate"] == Kalcifer.Engine.Nodes.Condition.PreferenceGate
      assert all["track_conversion"] == Kalcifer.Engine.Nodes.Action.Data.TrackConversion
    end
  end

  describe "register/2" do
    test "registers a custom node type" do
      NodeRegistry.register("test_custom", Kalcifer.Engine.Nodes.End.Exit)

      assert {:ok, Kalcifer.Engine.Nodes.End.Exit} =
               NodeRegistry.lookup("test_custom")
    end
  end
end
