defmodule Kalcifer.Engine.NodeRegistryTest do
  use ExUnit.Case, async: false

  alias Kalcifer.Engine.NodeRegistry

  describe "lookup/1" do
    test "returns module for registered node type" do
      assert {:ok, Kalcifer.Engine.Nodes.StartEvent.EventEntry} =
               NodeRegistry.lookup("event_entry")
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

    test "includes all start_event nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["event_entry"] == Kalcifer.Engine.Nodes.StartEvent.EventEntry
      assert all["segment_entry"] == Kalcifer.Engine.Nodes.StartEvent.SegmentEntry
      assert all["webhook_entry"] == Kalcifer.Engine.Nodes.StartEvent.WebhookEntry
    end

    test "includes all task/channel nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["send_email"] == Kalcifer.Engine.Nodes.Task.Channel.SendEmail
      assert all["send_sms"] == Kalcifer.Engine.Nodes.Task.Channel.SendSms
      assert all["send_push"] == Kalcifer.Engine.Nodes.Task.Channel.SendPush
      assert all["send_whatsapp"] == Kalcifer.Engine.Nodes.Task.Channel.SendWhatsapp
      assert all["call_webhook"] == Kalcifer.Engine.Nodes.Task.Channel.CallWebhook
    end

    test "includes all gateway and intermediate_event nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["condition"] == Kalcifer.Engine.Nodes.Gateway.Condition
      assert all["ab_split"] == Kalcifer.Engine.Nodes.Gateway.AbSplit
      assert all["frequency_cap"] == Kalcifer.Engine.Nodes.Gateway.FrequencyCap
      assert all["wait"] == Kalcifer.Engine.Nodes.IntermediateEvent.Wait
      assert all["wait_until"] == Kalcifer.Engine.Nodes.IntermediateEvent.WaitUntil
      assert all["wait_for_event"] == Kalcifer.Engine.Nodes.IntermediateEvent.WaitForEvent
    end

    test "includes all task/data and end_event nodes" do
      all = Map.new(NodeRegistry.list_all())
      assert all["update_profile"] == Kalcifer.Engine.Nodes.Task.Data.UpdateProfile
      assert all["add_tag"] == Kalcifer.Engine.Nodes.Task.Data.AddTag
      assert all["custom_code"] == Kalcifer.Engine.Nodes.Task.Data.CustomCode
      assert all["journey_exit"] == Kalcifer.Engine.Nodes.EndEvent.JourneyExit
      assert all["goal_reached"] == Kalcifer.Engine.Nodes.EndEvent.GoalReached
    end
  end

  describe "register/2" do
    test "registers a custom node type" do
      NodeRegistry.register("test_custom", Kalcifer.Engine.Nodes.EndEvent.JourneyExit)

      assert {:ok, Kalcifer.Engine.Nodes.EndEvent.JourneyExit} =
               NodeRegistry.lookup("test_custom")
    end
  end
end
