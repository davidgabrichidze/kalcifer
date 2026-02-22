defmodule Kalcifer.Factory do
  @moduledoc false

  use ExMachina.Ecto, repo: Kalcifer.Repo

  alias Kalcifer.Journeys.ExecutionStep
  alias Kalcifer.Journeys.Journey
  alias Kalcifer.Journeys.JourneyInstance
  alias Kalcifer.Journeys.JourneyVersion
  alias Kalcifer.Tenants.Tenant

  def tenant_factory do
    %Tenant{
      name: sequence(:tenant_name, &"Tenant #{&1}"),
      api_key_hash: sequence(:api_key_hash, &"hashed_key_#{&1}"),
      settings: %{}
    }
  end

  def journey_factory do
    %Journey{
      name: sequence(:journey_name, &"Journey #{&1}"),
      description: "A test journey",
      status: "draft",
      tenant: build(:tenant),
      entry_config: %{},
      exit_criteria: %{},
      frequency_cap: %{}
    }
  end

  def journey_version_factory do
    %JourneyVersion{
      version_number: 1,
      graph: valid_graph(),
      status: "draft",
      changelog: "Initial version",
      journey: build(:journey)
    }
  end

  def journey_instance_factory do
    %JourneyInstance{
      version_number: 1,
      customer_id: sequence(:customer_id, &"customer_#{&1}"),
      status: "running",
      current_nodes: ["entry_1"],
      context: %{},
      entered_at: DateTime.utc_now() |> DateTime.truncate(:second),
      journey: build(:journey),
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
      instance: build(:journey_instance)
    }
  end

  @doc """
  Returns a minimal valid journey graph: entry → exit.
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
          "type" => "journey_exit",
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
        %{"id" => "exit_1", "type" => "journey_exit", "config" => %{}}
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
