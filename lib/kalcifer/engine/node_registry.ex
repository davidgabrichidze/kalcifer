defmodule Kalcifer.Engine.NodeRegistry do
  @moduledoc false

  use GenServer

  @table :kalcifer_node_registry

  @built_in_nodes %{
    "event_entry" => Kalcifer.Engine.Nodes.Trigger.EventEntry,
    "segment_entry" => Kalcifer.Engine.Nodes.Trigger.SegmentEntry,
    "webhook_entry" => Kalcifer.Engine.Nodes.Trigger.WebhookEntry,
    "send_email" => Kalcifer.Engine.Nodes.Action.Channel.SendEmail,
    "send_sms" => Kalcifer.Engine.Nodes.Action.Channel.SendSms,
    "send_push" => Kalcifer.Engine.Nodes.Action.Channel.SendPush,
    "send_whatsapp" => Kalcifer.Engine.Nodes.Action.Channel.SendWhatsapp,
    "call_webhook" => Kalcifer.Engine.Nodes.Action.Channel.CallWebhook,
    "wait" => Kalcifer.Engine.Nodes.Wait.Wait,
    "wait_until" => Kalcifer.Engine.Nodes.Wait.WaitUntil,
    "wait_for_event" => Kalcifer.Engine.Nodes.Wait.WaitForEvent,
    "condition" => Kalcifer.Engine.Nodes.Condition.Condition,
    "ab_split" => Kalcifer.Engine.Nodes.Condition.AbSplit,
    "frequency_cap" => Kalcifer.Engine.Nodes.Condition.FrequencyCap,
    "update_profile" => Kalcifer.Engine.Nodes.Action.Data.UpdateProfile,
    "add_tag" => Kalcifer.Engine.Nodes.Action.Data.AddTag,
    "custom_code" => Kalcifer.Engine.Nodes.Action.Data.CustomCode,
    "exit" => Kalcifer.Engine.Nodes.End.Exit,
    "goal_reached" => Kalcifer.Engine.Nodes.End.GoalReached
  }

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def lookup(type) do
    case :ets.lookup(@table, type) do
      [{^type, module}] -> {:ok, module}
      [] -> :error
    end
  end

  def register(type, module) do
    GenServer.call(__MODULE__, {:register, type, module})
  end

  def list_all do
    :ets.tab2list(@table)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])

    for {type, module} <- @built_in_nodes do
      :ets.insert(table, {type, module})
    end

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, type, module}, _from, state) do
    :ets.insert(state.table, {type, module})
    {:reply, :ok, state}
  end
end
