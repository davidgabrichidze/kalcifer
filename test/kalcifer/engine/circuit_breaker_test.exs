defmodule Kalcifer.Engine.CircuitBreakerTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.CircuitBreaker

  setup do
    {:ok, pid} = CircuitBreaker.start_link(name: :"cb_#{System.unique_integer()}")
    %{cb: pid}
  end

  test "starts in closed state", %{cb: cb} do
    assert CircuitBreaker.status(cb, :email) == :closed
  end

  test "allows requests when closed", %{cb: cb} do
    assert CircuitBreaker.allow?(cb, :email) == true
  end

  test "opens circuit after threshold failures", %{cb: cb} do
    Enum.each(1..5, fn _ ->
      CircuitBreaker.record_failure(cb, :email)
    end)

    # Give GenServer time to process casts
    Process.sleep(10)

    assert CircuitBreaker.status(cb, :email) == :open
    assert CircuitBreaker.allow?(cb, :email) == false
  end

  test "success resets failure count", %{cb: cb} do
    Enum.each(1..4, fn _ ->
      CircuitBreaker.record_failure(cb, :email)
    end)

    CircuitBreaker.record_success(cb, :email)
    Process.sleep(10)

    assert CircuitBreaker.status(cb, :email) == :closed
    assert CircuitBreaker.allow?(cb, :email) == true
  end

  test "different channels are independent", %{cb: cb} do
    Enum.each(1..5, fn _ ->
      CircuitBreaker.record_failure(cb, :email)
    end)

    Process.sleep(10)

    assert CircuitBreaker.status(cb, :email) == :open
    assert CircuitBreaker.status(cb, :sms) == :closed
  end
end
