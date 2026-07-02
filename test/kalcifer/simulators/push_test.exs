defmodule Kalcifer.Simulators.PushTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Simulators.Push

  describe "plan/1" do
    test "deliver scenario" do
      assert [%{status: "delivered"}] = Push.plan(%{"simulate" => "deliver"})
    end

    test "tap scenario delivers then records a tap" do
      assert [%{status: "delivered"}, %{event: %{"type" => "tap"}}] =
               Push.plan(%{"simulate" => "tap"})
    end

    test "invalid token fails with UNREGISTERED event" do
      assert [%{status: "failed", event: %{"type" => "invalid_token", "code" => "UNREGISTERED"}}] =
               Push.plan(%{"simulate" => "invalid_token"})
    end

    test "random plans always start with a terminal status step" do
      for _ <- 1..50 do
        assert [%{status: status} | _] = Push.plan(%{})
        assert status in ["delivered", "failed"]
      end
    end
  end
end
