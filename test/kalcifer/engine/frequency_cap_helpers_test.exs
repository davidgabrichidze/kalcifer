defmodule Kalcifer.Engine.FrequencyCapHelpersTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.FrequencyCapHelpers

  describe "parse_time_window/1" do
    test "returns {:ok, datetime} for valid duration" do
      before = DateTime.utc_now()
      assert {:ok, %DateTime{} = dt} = FrequencyCapHelpers.parse_time_window("24h")
      assert DateTime.compare(dt, before) == :lt
    end

    test "returns error for invalid duration" do
      assert {:error, :invalid_time_window} = FrequencyCapHelpers.parse_time_window("???")
    end

    test "returns error for nil" do
      assert {:error, :invalid_time_window} = FrequencyCapHelpers.parse_time_window(nil)
    end
  end

  describe "resolve_channel_types/1" do
    test "returns types for known channel" do
      assert {:ok, ["send_email"]} = FrequencyCapHelpers.resolve_channel_types("email")
      assert {:ok, ["send_sms"]} = FrequencyCapHelpers.resolve_channel_types("sms")
    end

    test "returns all types for 'all'" do
      assert {:ok, types} = FrequencyCapHelpers.resolve_channel_types("all")
      assert length(types) == 6
      assert "send_email" in types
      assert "send_sms" in types
      assert "send_push" in types
    end

    test "returns error for unknown channel" do
      assert {:error, {:unknown_channel, "fax"}} =
               FrequencyCapHelpers.resolve_channel_types("fax")
    end
  end
end
