defmodule Kalcifer.Factory do
  @moduledoc false

  use ExMachina.Ecto, repo: Kalcifer.Repo

  alias Kalcifer.Flows.ExecutionStep
  alias Kalcifer.Flows.Flow
  alias Kalcifer.Flows.FlowInstance
  alias Kalcifer.Flows.FlowVersion
  alias Kalcifer.Tenants.Tenant

  def tenant_factory do
    %Tenant{
      name: sequence(:tenant_name, &"Tenant #{&1}"),
      api_key_hash: sequence(:api_key_hash, &"hashed_key_#{&1}"),
      settings: %{}
    }
  end

  def flow_factory do
    %Flow{
      name: sequence(:flow_name, &"Flow #{&1}"),
      description: "A test flow",
      status: "draft",
      tenant: build(:tenant),
      entry_config: %{},
      exit_criteria: %{},
      frequency_cap: %{}
    }
  end

  def flow_version_factory do
    %FlowVersion{
      version_number: 1,
      graph: valid_graph(),
      status: "draft",
      changelog: "Initial version",
      flow: build(:flow)
    }
  end

  def flow_instance_factory do
    %FlowInstance{
      version_number: 1,
      customer_id: sequence(:customer_id, &"customer_#{&1}"),
      status: "running",
      current_nodes: ["entry_1"],
      context: %{},
      entered_at: DateTime.utc_now() |> DateTime.truncate(:second),
      flow: build(:flow),
      tenant: build(:tenant)
    }
  end

  def execution_step_factory do
    %ExecutionStep{
      node_id: "entry_1",
      node_type: "event_entry",
      version_number: 1,
      status: "completed",
      input: %{},
      output: %{},
      started_at: DateTime.utc_now() |> DateTime.truncate(:second),
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      instance: build(:flow_instance)
    }
  end

  @doc """
  Returns a minimal valid flow graph: entry → exit.
  """
  def valid_graph do
    %{
      "nodes" => [
        %{
          "id" => "entry_1",
          "type" => "event_entry",
          "position" => %{"x" => 0, "y" => 0},
          "config" => %{"event_type" => "signed_up"}
        },
        %{
          "id" => "exit_1",
          "type" => "exit",
          "position" => %{"x" => 200, "y" => 0},
          "config" => %{}
        }
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "exit_1"}
      ]
    }
  end

  @doc """
  Returns a graph with a branching wait_for_event node.
  """
  def branching_graph do
    %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "signed_up"}},
        %{
          "id" => "wait_1",
          "type" => "wait_for_event",
          "config" => %{"event_type" => "email_opened", "timeout" => "3d"}
        },
        %{"id" => "email_1", "type" => "send_email", "config" => %{"template_id" => "followup"}},
        %{"id" => "email_2", "type" => "send_email", "config" => %{"template_id" => "reminder"}},
        %{"id" => "exit_1", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"id" => "e1", "source" => "entry_1", "target" => "wait_1"},
        %{
          "id" => "e2",
          "source" => "wait_1",
          "target" => "email_1",
          "branch" => "event_received"
        },
        %{"id" => "e3", "source" => "wait_1", "target" => "email_2", "branch" => "timed_out"},
        %{"id" => "e4", "source" => "email_1", "target" => "exit_1"},
        %{"id" => "e5", "source" => "email_2", "target" => "exit_1"}
      ]
    }
  end
end
