defmodule Kalcifer.Engine.ErrorCatalog do
  @moduledoc false

  # --- Node execution errors ---

  def humanize(%{reason: reason, stacktrace: _stacktrace}) do
    %{
      message: humanize_exception(reason),
      category: "execution_error",
      suggestion:
        "Check the node configuration and retry. If the problem persists, contact support."
    }
  end

  def humanize(%{reason: reason}) when is_binary(reason) do
    humanize_reason_string(reason)
  end

  def humanize(%{} = error) do
    %{
      message: "An unexpected error occurred: #{inspect(error)}",
      category: "unknown",
      suggestion: "Contact support with this error details."
    }
  end

  def humanize(nil), do: nil

  # --- Flow trigger errors ---

  def humanize_code(:not_found) do
    %{
      code: "not_found",
      message: "Flow not found.",
      suggestion: "Check that the flow ID is correct."
    }
  end

  def humanize_code(:flow_not_active) do
    %{
      code: "flow_not_active",
      message: "This flow is not active. Only active flows can be triggered.",
      suggestion: "Activate the flow first, then try again."
    }
  end

  def humanize_code(:no_active_version) do
    %{
      code: "no_active_version",
      message: "This flow has no published version.",
      suggestion: "Publish a version of this flow before triggering it."
    }
  end

  def humanize_code(:already_in_flow) do
    %{
      code: "already_in_flow",
      message: "This customer is already in this flow.",
      suggestion: "Wait for the current run to complete, or cancel it first."
    }
  end

  def humanize_code(:frequency_cap_exceeded) do
    %{
      code: "frequency_cap_exceeded",
      message: "Message limit reached for this customer.",
      suggestion:
        "The customer has received the maximum number of messages in the configured time window."
    }
  end

  def humanize_code(:not_draft) do
    %{
      code: "not_draft",
      message: "This flow is not in draft status and cannot be edited.",
      suggestion: "Only draft flows can be modified. Create a new version instead."
    }
  end

  def humanize_code(:no_draft_version) do
    %{
      code: "no_draft_version",
      message: "No draft version found for this flow.",
      suggestion: "Create a new draft version first."
    }
  end

  def humanize_code(:version_not_found) do
    %{
      code: "version_not_found",
      message: "The specified version does not exist.",
      suggestion: "Check the version number and try again."
    }
  end

  def humanize_code(:version_not_publishable) do
    %{
      code: "version_not_publishable",
      message: "This version cannot be published.",
      suggestion: "Run preflight checks to see what needs to be fixed."
    }
  end

  def humanize_code(code) when is_atom(code) do
    %{
      code: to_string(code),
      message: "An error occurred: #{code}.",
      suggestion: nil
    }
  end

  # --- Node failure reasons (from ExecutionStep.error.reason) ---

  defp humanize_reason_string(reason) do
    cond do
      String.contains?(reason, "tag_failed") ->
        %{
          message: "Failed to add tag to customer profile.",
          category: "data_error",
          suggestion: "Check that the tag value is valid."
        }

      String.contains?(reason, "update_failed") ->
        %{
          message: "Failed to update customer profile.",
          category: "data_error",
          suggestion: "Check that the field names and values are valid."
        }

      String.contains?(reason, "no_variants") ->
        %{
          message: "A/B split has no variants configured.",
          category: "config_error",
          suggestion: "Add at least one variant to the A/B split node."
        }

      String.contains?(reason, "not_resumable") ->
        %{
          message: "This node cannot be resumed.",
          category: "execution_error",
          suggestion: "This is an internal error. The node type does not support resume."
        }

      String.contains?(reason, "unexpected_trigger") ->
        %{
          message: "Wait node received an unexpected trigger.",
          category: "execution_error",
          suggestion:
            "This usually resolves on its own. If it persists, check the flow configuration."
        }

      String.contains?(reason, "unknown_node_type") ->
        %{
          message: "Unknown node type in the flow.",
          category: "config_error",
          suggestion:
            "The flow contains a node type that is not registered. Check the flow graph."
        }

      String.contains?(reason, "no_provider") ->
        %{
          message: "No message provider configured for this channel.",
          category: "config_error",
          suggestion:
            "Set up a provider (e.g., SendGrid for email, Twilio for SMS) in your settings."
        }

      String.contains?(reason, "server_crashed") ->
        %{
          message: "The flow execution was interrupted unexpectedly.",
          category: "system_error",
          suggestion: "This was an internal error. You can re-trigger the flow for this customer."
        }

      true ->
        %{
          message: "Node execution failed: #{truncate(reason, 200)}",
          category: "execution_error",
          suggestion: "Check the node configuration. If the error persists, contact support."
        }
    end
  end

  defp humanize_exception(reason) when is_binary(reason) do
    cond do
      String.contains?(reason, "DBConnection") or String.contains?(reason, "Postgrex") ->
        "Database connection error. The system may be temporarily unavailable."

      String.contains?(reason, "timeout") ->
        "The operation timed out. This may be due to high load."

      String.contains?(reason, "HTTPoison") or String.contains?(reason, "Finch") ->
        "Failed to connect to an external service."

      true ->
        "Internal error: #{truncate(reason, 200)}"
    end
  end

  defp humanize_exception(reason), do: "Internal error: #{truncate(inspect(reason), 200)}"

  defp truncate(string, max) when byte_size(string) > max do
    String.slice(string, 0, max) <> "..."
  end

  defp truncate(string, _max), do: string
end
