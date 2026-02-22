defmodule Kalcifer.Engine.NodesTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Action.Channel.CallWebhook
  alias Kalcifer.Engine.Nodes.Action.Channel.SendEmail
  alias Kalcifer.Engine.Nodes.Action.Channel.SendPush
  alias Kalcifer.Engine.Nodes.Action.Channel.SendSms
  alias Kalcifer.Engine.Nodes.Action.Channel.SendWhatsapp
  alias Kalcifer.Engine.Nodes.Action.Data.AddTag
  alias Kalcifer.Engine.Nodes.Action.Data.CustomCode
  alias Kalcifer.Engine.Nodes.Action.Data.UpdateProfile
  alias Kalcifer.Engine.Nodes.Condition.AbSplit
  alias Kalcifer.Engine.Nodes.Condition.Condition
  alias Kalcifer.Engine.Nodes.Condition.FrequencyCap
  alias Kalcifer.Engine.Nodes.End.Exit
  alias Kalcifer.Engine.Nodes.End.GoalReached
  alias Kalcifer.Engine.Nodes.Trigger.EventEntry
  alias Kalcifer.Engine.Nodes.Trigger.SegmentEntry
  alias Kalcifer.Engine.Nodes.Trigger.WebhookEntry
  alias Kalcifer.Engine.Nodes.Wait.Wait
  alias Kalcifer.Engine.Nodes.Wait.WaitForEvent
  alias Kalcifer.Engine.Nodes.Wait.WaitUntil

  describe "trigger nodes" do
    test "event_entry returns completed with event_type" do
      assert {:completed, %{event_type: "signed_up"}} =
               EventEntry.execute(%{"event_type" => "signed_up"}, %{})
    end

    test "event_entry category is :trigger" do
      assert EventEntry.category() == :trigger
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

  describe "action/channel nodes" do
    test "send_email returns completed" do
      assert {:completed, %{sent: true, channel: "email"}} =
               SendEmail.execute(%{"template_id" => "t1"}, %{})
    end

    test "send_email category is :action" do
      assert SendEmail.category() == :action
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

  describe "condition nodes" do
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

    test "condition category is :condition" do
      assert Condition.category() == :condition
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

    test "ab_split category is :condition" do
      assert AbSplit.category() == :condition
    end

    test "frequency_cap returns branched allowed" do
      assert {:branched, "allowed", %{capped: false}} = FrequencyCap.execute(%{}, %{})
    end
  end

  describe "wait nodes" do
    test "wait returns waiting with duration" do
      assert {:waiting, %{duration: "3d"}} = Wait.execute(%{"duration" => "3d"}, %{})
    end

    test "wait resume returns completed" do
      assert {:completed, %{waited: true}} = Wait.resume(%{}, %{}, :timer_expired)
    end

    test "wait category is :wait" do
      assert Wait.category() == :wait
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

  describe "action/data nodes" do
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

  describe "end nodes" do
    test "exit returns completed with exit flag" do
      assert {:completed, %{exit: true}} = Exit.execute(%{}, %{})
    end

    test "exit category is :end" do
      assert Exit.category() == :end
    end

    test "goal_reached returns completed with goal name" do
      assert {:completed, %{exit: true, goal: "purchase"}} =
               GoalReached.execute(%{"goal_name" => "purchase"}, %{})
    end
  end
end
