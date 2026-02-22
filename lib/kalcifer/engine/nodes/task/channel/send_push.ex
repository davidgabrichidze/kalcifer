defmodule Kalcifer.Engine.Nodes.Task.Channel.SendPush do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:completed, %{sent: true, channel: "push", template_id: config["template_id"]}}
  end

  @impl true
  def config_schema do
    %{"template_id" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :task
end
