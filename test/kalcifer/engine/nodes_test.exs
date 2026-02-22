defmodule Kalcifer.Engine.NodesTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.EndEvent.GoalReached
  alias Kalcifer.Engine.Nodes.EndEvent.JourneyExit
  alias Kalcifer.Engine.Nodes.Gateway.AbSplit
  alias Kalcifer.Engine.Nodes.Gateway.Condition
  alias Kalcifer.Engine.Nodes.Gateway.FrequencyCap
  alias Kalcifer.Engine.Nodes.IntermediateEvent.Wait
  alias Kalcifer.Engine.Nodes.IntermediateEvent.WaitForEvent
  alias Kalcifer.Engine.Nodes.IntermediateEvent.WaitUntil
  alias Kalcifer.Engine.Nodes.StartEvent.EventEntry
  alias Kalcifer.Engine.Nodes.StartEvent.SegmentEntry
  alias Kalcifer.Engine.Nodes.StartEvent.WebhookEntry
  alias Kalcifer.Engine.Nodes.Task.Channel.CallWebhook
  alias Kalcifer.Engine.Nodes.Task.Channel.SendEmail
  alias Kalcifer.Engine.Nodes.Task.Channel.SendPush
  alias Kalcifer.Engine.Nodes.Task.Channel.SendSms
  alias Kalcifer.Engine.Nodes.Task.Channel.SendWhatsapp
  alias Kalcifer.Engine.Nodes.Task.Data.AddTag
  alias Kalcifer.Engine.Nodes.Task.Data.CustomCode
  alias Kalcifer.Engine.Nodes.Task.Data.UpdateProfile

  describe "start_event nodes" do
    test "event_entry returns completed with event_type" do
      assert {:completed, %{event_type: "signed_up"}} =
               EventEntry.execute(%{"event_type" => "signed_up"}, %{})
    end

    test "event_entry category is :start_event" do
      assert EventEntry.category() == :start_event
    end

    test "segment_entry returns completed with segment_id" do
      assert {:completed, %{segment_id: "seg_1"}} =
               SegmentEntry.execute(%{"segment_id" => "seg_1"}, %{})
    end

    test "webhook_entry returns completed with webhook_path" do
      assert {:completed, %{webhook_path: "/hooks/test"}} =
               WebhookEntry.execute(%{"webhook_path" => "/hooks/test"}, %{})
    end
  end

  describe "task/channel nodes" do
    test "send_email returns completed" do
      assert {:completed, %{sent: true, channel: "email"}} =
               SendEmail.execute(%{"template_id" => "t1"}, %{})
    end

    test "send_email category is :task" do
      assert SendEmail.category() == :task
    end

    test "send_sms returns completed" do
      assert {:completed, %{sent: true, channel: "sms"}} =
               SendSms.execute(%{"template_id" => "t1"}, %{})
    end

    test "send_push returns completed" do
      assert {:completed, %{sent: true, channel: "push"}} =
               SendPush.execute(%{"template_id" => "t1"}, %{})
    end

    test "send_whatsapp returns completed" do
      assert {:completed, %{sent: true, channel: "whatsapp"}} =
               SendWhatsapp.execute(%{"template_id" => "t1"}, %{})
    end

    test "call_webhook returns completed" do
      assert {:completed, %{sent: true, channel: "webhook"}} =
               CallWebhook.execute(%{"url" => "https://example.com"}, %{})
    end
  end

  describe "gateway nodes" do
    test "condition branches true when field matches" do
      config = %{"field" => "status", "value" => "active"}
      context = %{"status" => "active"}
      assert {:branched, "true", %{matched: true}} = Condition.execute(config, context)
    end

    test "condition branches false when field does not match" do
      config = %{"field" => "status", "value" => "active"}
      context = %{"status" => "inactive"}
      assert {:branched, "false", %{matched: false}} = Condition.execute(config, context)
    end

    test "condition category is :gateway" do
      assert Condition.category() == :gateway
    end

    test "ab_split returns branched with a variant key" do
      config = %{
        "variants" => [
          %{"key" => "a", "weight" => 50},
          %{"key" => "b", "weight" => 50}
        ]
      }

      assert {:branched, key, %{selected_variant: key}} = AbSplit.execute(config, %{})
      assert key in ["a", "b"]
    end

    test "ab_split category is :gateway" do
      assert AbSplit.category() == :gateway
    end

    test "frequency_cap returns branched allowed" do
      assert {:branched, "allowed", %{capped: false}} = FrequencyCap.execute(%{}, %{})
    end
  end

  describe "intermediate_event nodes" do
    test "wait returns waiting with duration" do
      assert {:waiting, %{duration: "3d"}} = Wait.execute(%{"duration" => "3d"}, %{})
    end

    test "wait resume returns completed" do
      assert {:completed, %{waited: true}} = Wait.resume(%{}, %{}, :timer_expired)
    end

    test "wait category is :intermediate_event" do
      assert Wait.category() == :intermediate_event
    end

    test "wait_until returns waiting with datetime" do
      assert {:waiting, %{until: "2026-03-01T10:00:00Z"}} =
               WaitUntil.execute(%{"datetime" => "2026-03-01T10:00:00Z"}, %{})
    end

    test "wait_for_event returns waiting" do
      config = %{"event_type" => "email_opened", "timeout" => "3d"}
      assert {:waiting, %{event_type: "email_opened"}} = WaitForEvent.execute(config, %{})
    end

    test "wait_for_event resume with event returns event_received branch" do
      trigger = %{event_type: "email_opened"}

      assert {:branched, "event_received", _} = WaitForEvent.resume(%{}, %{}, trigger)
    end

    test "wait_for_event resume with timeout returns timed_out branch" do
      assert {:branched, "timed_out", %{timed_out: true}} =
               WaitForEvent.resume(%{}, %{}, :timeout)
    end
  end

  describe "task/data nodes" do
    test "update_profile returns completed" do
      assert {:completed, %{updated: true}} =
               UpdateProfile.execute(%{"fields" => %{"name" => "Test"}}, %{})
    end

    test "add_tag returns completed" do
      assert {:completed, %{tagged: true, tag: "vip"}} =
               AddTag.execute(%{"tag" => "vip"}, %{})
    end

    test "custom_code returns completed" do
      assert {:completed, %{executed: true}} = CustomCode.execute(%{}, %{})
    end
  end

  describe "end_event nodes" do
    test "journey_exit returns completed with exit flag" do
      assert {:completed, %{exit: true}} = JourneyExit.execute(%{}, %{})
    end

    test "journey_exit category is :end_event" do
      assert JourneyExit.category() == :end_event
    end

    test "goal_reached returns completed with goal name" do
      assert {:completed, %{exit: true, goal: "purchase"}} =
               GoalReached.execute(%{"goal_name" => "purchase"}, %{})
    end
  end
end
