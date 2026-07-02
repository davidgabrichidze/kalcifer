defmodule Kalcifer.Simulators.InAppTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Simulators.InApp

  describe "plan/1" do
    test "deliver scenario delivers on session start" do
      assert [%{status: "delivered", event: %{"type" => "session_start"}}] =
               InApp.plan(%{"simulate" => "deliver"})
    end

    test "seen scenario delivers then marks seen" do
      assert [%{status: "delivered"}, %{event: %{"type" => "seen"}}] =
               InApp.plan(%{"simulate" => "seen"})
    end

    test "expire scenario fails with no_session reason" do
      assert [%{status: "failed", event: %{"type" => "expired", "reason" => "no_session"}}] =
               InApp.plan(%{"simulate" => "expire"})
    end

    test "random plans always start with a terminal status step" do
      for _ <- 1..50 do
        assert [%{status: status} | _] = InApp.plan(%{})
        assert status in ["delivered", "failed"]
      end
    end
  end
end
