defmodule Kalcifer.Engine.Nodes.Task.Channel.CallWebhook do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:completed, %{sent: true, channel: "webhook", url: config["url"]}}
  end

  @impl true
  def config_schema do
    %{
      "url" => %{"type" => "string", "required" => true},
      "method" => %{"type" => "string", "default" => "POST"},
      "headers" => %{"type" => "object"}
    }
  end

  @impl true
  def category, do: :task
end
