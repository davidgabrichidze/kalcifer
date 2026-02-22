defmodule Kalcifer.Engine.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Kalcifer.Engine.ProcessRegistry},
      Kalcifer.Engine.NodeRegistry,
      {DynamicSupervisor, name: Kalcifer.Engine.FlowSupervisor, strategy: :one_for_one},
      Kalcifer.Engine.RecoveryManager
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
