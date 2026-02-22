defmodule Kalcifer.Engine.Nodes.Trigger.WebhookEntry do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:completed, %{webhook_path: config["webhook_path"]}}
  end

  @impl true
  def config_schema do
    %{"webhook_path" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :trigger
end
