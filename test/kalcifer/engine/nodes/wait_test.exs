defmodule Kalcifer.Engine.Nodes.Wait.WaitTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Wait.Wait
  alias Kalcifer.Engine.Nodes.Wait.WaitForEvent
  alias Kalcifer.Engine.Nodes.Wait.WaitUntil

  # --- Wait (Duration) ---

  describe "Wait.execute/2" do
    test "returns waiting config with duration" do
      config = %{"duration" => "2h"}
      assert {:waiting, %{duration: "2h"}} = Wait.execute(config, %{})
    end

    test "dry_run skips wait and returns completed" do
      config = %{"duration" => "2h"}
      assert {:completed, result} = Wait.execute(config, %{"_dry_run" => true})
      assert result.dry_run == true
      assert result.skipped_wait == "2h"
    end
  end

  describe "Wait.resume/3" do
    test "timer_expired returns completed" do
      assert {:completed, %{waited: true}} = Wait.resume(%{}, %{}, :timer_expired)
    end

    test "unexpected trigger returns failed" do
      assert {:failed, :unexpected_trigger} = Wait.resume(%{}, %{}, :unknown)
    end
  end

  describe "Wait.category/0" do
    test "returns :wait" do
      assert Wait.category() == :wait
    end
  end

  # --- WaitUntil ---

  describe "WaitUntil.execute/2" do
    test "returns waiting config with datetime" do
      dt = DateTime.utc_now() |> DateTime.add(7200) |> DateTime.to_iso8601()
      config = %{"datetime" => dt}
      assert {:waiting, %{until: ^dt}} = WaitUntil.execute(config, %{})
    end

    test "dry_run skips wait" do
      config = %{"datetime" => "2026-04-01T00:00:00Z"}
      assert {:completed, result} = WaitUntil.execute(config, %{"_dry_run" => true})
      assert result.dry_run == true
    end
  end

  describe "WaitUntil.resume/3" do
    test "timer_expired returns completed" do
      assert {:completed, %{waited: true}} = WaitUntil.resume(%{}, %{}, :timer_expired)
    end
  end

  describe "WaitUntil.category/0" do
    test "returns :wait" do
      assert WaitUntil.category() == :wait
    end
  end

  # --- WaitForEvent ---

  describe "WaitForEvent.execute/2" do
    test "registers wait with event type" do
      config = %{"event_type" => "purchase"}
      assert {:waiting, %{event_type: "purchase"}} = WaitForEvent.execute(config, %{})
    end

    test "dry_run follows event_received branch" do
      config = %{"event_type" => "purchase"}

      assert {:branched, "event_received", result} =
               WaitForEvent.execute(config, %{"_dry_run" => true})

      assert result.dry_run == true
    end
  end

  describe "WaitForEvent.resume/3" do
    test "event received returns branched event_received" do
      event_data = %{email_id: "abc"}

      assert {:branched, "event_received", %{trigger: ^event_data}} =
               WaitForEvent.resume(%{}, %{}, event_data)
    end

    test "timeout returns branched timed_out" do
      assert {:branched, "timed_out", %{timed_out: true}} =
               WaitForEvent.resume(%{}, %{}, :timeout)
    end
  end

  describe "WaitForEvent.category/0" do
    test "returns :wait" do
      assert WaitForEvent.category() == :wait
    end
  end
end
