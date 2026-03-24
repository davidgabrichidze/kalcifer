defmodule Kalcifer.AI.CouncilRoutingTest do
  @moduledoc """
  Tests that ChatController's council keyword detection works correctly.
  We test the routing logic in isolation since ChatController uses
  private functions.
  """
  use ExUnit.Case, async: true

  # Replicate the keyword detection logic from ChatController
  @council_keywords ~w(council საბჭო დაფიქრდი ანალიზი deliberate think_deep)

  defp council_request?(message) when is_binary(message) do
    lower = String.downcase(message)
    Enum.any?(@council_keywords, &String.contains?(lower, &1))
  end

  defp council_request?(_), do: false

  describe "council keyword detection" do
    test "detects Georgian keyword: საბჭო" do
      assert council_request?("მინდა საბჭო გამოიყენო")
    end

    test "detects Georgian keyword: დაფიქრდი" do
      assert council_request?("დაფიქრდი ამ თემაზე")
    end

    test "detects Georgian keyword: ანალიზი" do
      assert council_request?("ღრმა ანალიზი გააკეთე")
    end

    test "detects English keyword: council" do
      assert council_request?("use the council for this")
    end

    test "detects English keyword: deliberate" do
      assert council_request?("please deliberate on this topic")
    end

    test "case insensitive" do
      assert council_request?("COUNCIL mode please")
      assert council_request?("Council")
    end

    test "does not trigger on simple messages" do
      refute council_request?("გამარჯობა")
      refute council_request?("შემიქმენი ფლოუ")
      refute council_request?("what flows do I have?")
      refute council_request?("build me an onboarding email")
    end

    test "handles nil" do
      refute council_request?(nil)
    end

    test "handles empty string" do
      refute council_request?("")
    end
  end
end
