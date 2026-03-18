defmodule Kalcifer.Engine.ErrorCatalogTest do
  use ExUnit.Case, async: true

  alias Kalcifer.Engine.ErrorCatalog

  describe "humanize/1 for execution step errors" do
    test "handles error with reason and stacktrace" do
      error = %{reason: "some exception", stacktrace: "..."}
      result = ErrorCatalog.humanize(error)

      assert result.category == "execution_error"
      assert is_binary(result.message)
      assert is_binary(result.suggestion)
    end

    test "handles tag_failed reason" do
      result = ErrorCatalog.humanize(%{reason: ":tag_failed"})

      assert result.category == "data_error"
      assert result.message =~ "tag"
    end

    test "handles update_failed reason" do
      result = ErrorCatalog.humanize(%{reason: ":update_failed"})

      assert result.category == "data_error"
      assert result.message =~ "update"
    end

    test "handles no_variants reason" do
      result = ErrorCatalog.humanize(%{reason: ":no_variants"})

      assert result.category == "config_error"
      assert result.message =~ "A/B"
    end

    test "handles unknown_node_type reason" do
      result = ErrorCatalog.humanize(%{reason: "{:unknown_node_type, \"bad_type\"}"})

      assert result.category == "config_error"
      assert result.message =~ "Unknown node type"
    end

    test "handles no_provider reason" do
      result = ErrorCatalog.humanize(%{reason: "{:no_provider, :email}"})

      assert result.category == "config_error"
      assert result.message =~ "provider"
    end

    test "handles server_crashed reason" do
      result = ErrorCatalog.humanize(%{reason: "server_crashed"})

      assert result.category == "system_error"
      assert result.message =~ "interrupted"
    end

    test "handles DB exception in stacktrace error" do
      error = %{reason: "DBConnection.ConnectionError: tcp connect", stacktrace: "..."}
      result = ErrorCatalog.humanize(error)

      assert result.message =~ "Database"
    end

    test "handles timeout exception" do
      error = %{reason: "timeout after 5000ms", stacktrace: "..."}
      result = ErrorCatalog.humanize(error)

      assert result.message =~ "timed out"
    end

    test "returns nil for nil input" do
      assert ErrorCatalog.humanize(nil) == nil
    end

    test "handles unknown error map" do
      result = ErrorCatalog.humanize(%{something: "weird"})

      assert result.category == "unknown"
      assert is_binary(result.message)
    end

    test "truncates long reason strings" do
      long_reason = String.duplicate("x", 500)
      result = ErrorCatalog.humanize(%{reason: long_reason})

      assert String.length(result.message) < 500
    end
  end

  describe "humanize_code/1 for trigger/API errors" do
    test "flow_not_active" do
      result = ErrorCatalog.humanize_code(:flow_not_active)

      assert result.code == "flow_not_active"
      assert result.message =~ "not active"
      assert is_binary(result.suggestion)
    end

    test "already_in_flow" do
      result = ErrorCatalog.humanize_code(:already_in_flow)

      assert result.code == "already_in_flow"
      assert result.message =~ "already"
    end

    test "frequency_cap_exceeded" do
      result = ErrorCatalog.humanize_code(:frequency_cap_exceeded)

      assert result.code == "frequency_cap_exceeded"
      assert result.message =~ "limit"
    end

    test "not_found" do
      result = ErrorCatalog.humanize_code(:not_found)

      assert result.code == "not_found"
      assert result.message =~ "not found"
    end

    test "no_active_version" do
      result = ErrorCatalog.humanize_code(:no_active_version)

      assert result.code == "no_active_version"
      assert result.message =~ "no published version"
    end

    test "unknown code falls back gracefully" do
      result = ErrorCatalog.humanize_code(:something_unexpected)

      assert result.code == "something_unexpected"
      assert is_binary(result.message)
    end
  end
end
