defmodule Kalcifer.Engine.DryRunTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.Engine.Nodes.Action.Channel.CallWebhook
  alias Kalcifer.Engine.Nodes.Action.Channel.SendEmail
  alias Kalcifer.Engine.Nodes.Action.Channel.SendInApp
  alias Kalcifer.Engine.Nodes.Action.Channel.SendPush
  alias Kalcifer.Engine.Nodes.Action.Channel.SendSms
  alias Kalcifer.Engine.Nodes.Action.Channel.SendWhatsapp
  alias Kalcifer.Engine.Nodes.Action.Data.AddTag
  alias Kalcifer.Engine.Nodes.Action.Data.CustomCode
  alias Kalcifer.Engine.Nodes.Action.Data.TrackConversion
  alias Kalcifer.Engine.Nodes.Action.Data.UpdateProfile
  alias Kalcifer.Engine.Nodes.Wait.Wait
  alias Kalcifer.Engine.Nodes.Wait.WaitForEvent
  alias Kalcifer.Engine.Nodes.Wait.WaitUntil

  defp dry_run_context(extra \\ %{}) do
    Map.merge(
      %{
        "_dry_run" => true,
        "_customer_id" => "cust_123",
        "_flow_id" => "flow_456",
        "_instance_id" => "inst_789",
        "_tenant_id" => "tenant_abc",
        "_email" => "test@example.com",
        "_phone" => "+15551234567"
      },
      extra
    )
  end

  describe "channel nodes in dry_run mode" do
    test "send_email returns would_send without creating delivery" do
      ctx = dry_run_context()

      assert {:completed, result} = SendEmail.execute(%{"template_id" => "welcome"}, ctx)
      assert result.dry_run == true
      assert result.would_send.channel == "email"
      assert result.would_send.template_id == "welcome"
      assert result.would_send.recipient == "test@example.com"
    end

    test "send_sms returns would_send with phone recipient" do
      ctx = dry_run_context()

      assert {:completed, result} = SendSms.execute(%{"template_id" => "otp"}, ctx)
      assert result.dry_run == true
      assert result.would_send.channel == "sms"
      assert result.would_send.recipient == "+15551234567"
    end

    test "send_push returns would_send" do
      ctx = dry_run_context()

      assert {:completed, result} = SendPush.execute(%{"template_id" => "promo"}, ctx)
      assert result.dry_run == true
      assert result.would_send.channel == "push"
    end

    test "send_whatsapp returns would_send with phone recipient" do
      ctx = dry_run_context()

      assert {:completed, result} = SendWhatsapp.execute(%{"template_id" => "order"}, ctx)
      assert result.dry_run == true
      assert result.would_send.channel == "whatsapp"
      assert result.would_send.recipient == "+15551234567"
    end

    test "send_in_app returns would_send with placement" do
      ctx = dry_run_context()
      config = %{"template_id" => "banner", "placement" => "top"}

      assert {:completed, result} = SendInApp.execute(config, ctx)
      assert result.dry_run == true
      assert result.would_send.channel == "in_app"
      assert result.would_send.placement == "top"
    end

    test "call_webhook returns would_call" do
      ctx = dry_run_context()

      assert {:completed, result} =
               CallWebhook.execute(%{"url" => "https://hook.example.com"}, ctx)

      assert result.dry_run == true
      assert result.would_call.channel == "webhook"
      assert result.would_call.url == "https://hook.example.com"
    end

    test "send_email falls back to customer_id when no email in context" do
      ctx = dry_run_context() |> Map.delete("_email")

      assert {:completed, result} = SendEmail.execute(%{"template_id" => "t1"}, ctx)
      assert result.would_send.recipient == "cust_123"
    end
  end

  describe "data nodes in dry_run mode" do
    test "update_profile returns would_update without touching DB" do
      ctx = dry_run_context()

      assert {:completed, result} =
               UpdateProfile.execute(%{"fields" => %{"name" => "Test", "tier" => "gold"}}, ctx)

      assert result.dry_run == true
      assert Enum.sort(result.would_update.fields) == ["name", "tier"]
      assert result.would_update.customer_id == "cust_123"
    end

    test "add_tag returns would_tag without touching DB" do
      ctx = dry_run_context()

      assert {:completed, result} = AddTag.execute(%{"tag" => "vip"}, ctx)
      assert result.dry_run == true
      assert result.would_tag == "vip"
      assert result.customer_id == "cust_123"
    end

    test "track_conversion returns would_track without inserting record" do
      ctx = dry_run_context()
      config = %{"event_name" => "purchase", "revenue" => 99.99}

      assert {:completed, result} = TrackConversion.execute(config, ctx)
      assert result.dry_run == true
      assert result.would_track.event_name == "purchase"
      assert result.would_track.revenue == 99.99
    end

    test "custom_code works normally in dry_run (no side effects anyway)" do
      ctx = dry_run_context()

      assert {:completed, %{executed: true}} = CustomCode.execute(%{}, ctx)
    end
  end

  describe "wait nodes in dry_run mode" do
    test "wait auto-completes instead of waiting" do
      ctx = dry_run_context()

      assert {:completed, result} = Wait.execute(%{"duration" => "3d"}, ctx)
      assert result.dry_run == true
      assert result.skipped_wait == "3d"
      assert result.waited == true
    end

    test "wait_until auto-completes instead of waiting" do
      ctx = dry_run_context()

      assert {:completed, result} =
               WaitUntil.execute(%{"datetime" => "2026-04-01T10:00:00Z"}, ctx)

      assert result.dry_run == true
      assert result.skipped_wait_until == "2026-04-01T10:00:00Z"
      assert result.waited == true
    end

    test "wait_for_event auto-branches event_received" do
      ctx = dry_run_context()
      config = %{"event_type" => "email_opened", "timeout" => "3d"}

      assert {:branched, "event_received", result} = WaitForEvent.execute(config, ctx)
      assert result.dry_run == true
      assert result.skipped_wait_for == "email_opened"
    end
  end

  describe "non-dry_run mode unchanged" do
    test "wait still returns waiting without dry_run flag" do
      assert {:waiting, %{duration: "3d"}} = Wait.execute(%{"duration" => "3d"}, %{})
    end

    test "wait_until still returns waiting without dry_run flag" do
      assert {:waiting, %{until: "2026-04-01T10:00:00Z"}} =
               WaitUntil.execute(%{"datetime" => "2026-04-01T10:00:00Z"}, %{})
    end

    test "wait_for_event still returns waiting without dry_run flag" do
      config = %{"event_type" => "email_opened", "timeout" => "3d"}
      assert {:waiting, %{event_type: "email_opened"}} = WaitForEvent.execute(config, %{})
    end
  end
end
