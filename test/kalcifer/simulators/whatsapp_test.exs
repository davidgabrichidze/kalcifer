defmodule Kalcifer.Simulators.WhatsappTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Simulators.Whatsapp

  describe "plan/1" do
    test "deliver scenario" do
      assert [%{status: "delivered"}] = Whatsapp.plan(%{"simulate" => "deliver"})
    end

    test "read scenario delivers then records a read receipt" do
      assert [%{status: "delivered"}, %{event: %{"type" => "read"}}] =
               Whatsapp.plan(%{"simulate" => "read"})
    end

    test "reply scenario reads then replies with a body" do
      assert [
               %{status: "delivered"},
               %{event: %{"type" => "read"}},
               %{event: %{"type" => "reply", "body" => body}}
             ] = Whatsapp.plan(%{"simulate" => "reply"})

      assert is_binary(body)
    end

    test "no_account fails with Twilio error code" do
      assert [%{status: "failed", event: %{"type" => "no_whatsapp_account", "code" => "63003"}}] =
               Whatsapp.plan(%{"simulate" => "no_account"})
    end

    test "random plans always start with a terminal status step" do
      for _ <- 1..50 do
        assert [%{status: status} | _] = Whatsapp.plan(%{})
        assert status in ["delivered", "failed"]
      end
    end
  end
end
