defmodule Kalcifer.Bugs.RecoveryTriggerMismatchTest do
  @moduledoc """
  N7 regression: RecoveryManager must send :timeout (not :timer_expired)
  for wait_for_event nodes. WaitForEvent.resume only matches :timeout
  for the timed_out branch.
  """
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Nodes.Wait.WaitForEvent

  test "WaitForEvent.resume with :timeout correctly branches as timed_out" do
    config = %{"event_type" => "email_opened", "timeout" => "3d"}
    context = %{}

    result = WaitForEvent.resume(config, context, :timeout)
    assert {:branched, "timed_out", _} = result
  end

  test "WaitForEvent.resume with :timer_expired branches as event_received (not timeout)" do
    config = %{"event_type" => "email_opened", "timeout" => "3d"}
    context = %{}

    # :timer_expired is NOT the timeout trigger for wait_for_event —
    # it falls through to the catch-all and branches as event_received.
    # RecoveryManager now sends :timeout instead.
    result = WaitForEvent.resume(config, context, :timer_expired)
    assert {:branched, "event_received", _} = result
  end
end
