defmodule Kalcifer.Engine.DurationTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.Duration

  describe "to_seconds/1" do
    test "parses seconds" do
      assert {:ok, 30} = Duration.to_seconds("30s")
    end

    test "parses minutes" do
      assert {:ok, 300} = Duration.to_seconds("5m")
    end

    test "parses hours" do
      assert {:ok, 7200} = Duration.to_seconds("2h")
    end

    test "parses days" do
      assert {:ok, 259_200} = Duration.to_seconds("3d")
    end

    test "parses weeks" do
      assert {:ok, 604_800} = Duration.to_seconds("1w")
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_duration} = Duration.to_seconds("abc")
    end

    test "returns error for missing unit" do
      assert {:error, :invalid_duration} = Duration.to_seconds("30")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_duration} = Duration.to_seconds("")
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_duration} = Duration.to_seconds(nil)
    end
  end

  describe "to_datetime/1" do
    test "returns a future datetime for valid duration" do
      before = DateTime.utc_now()
      assert {:ok, %DateTime{} = dt} = Duration.to_datetime("1h")
      assert DateTime.compare(dt, before) == :gt
    end

    test "returns error for invalid duration" do
      assert {:error, :invalid_duration} = Duration.to_datetime("invalid")
    end
  end
end
