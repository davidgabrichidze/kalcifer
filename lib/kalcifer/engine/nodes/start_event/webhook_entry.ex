defmodule Kalcifer.Engine.Nodes.StartEvent.WebhookEntry do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  @impl true
  def execute(config, _context) do
    {:completed, %{webhook_path: config["webhook_path"]}}
  end

  @impl true
  def validate(config) do
    if is_binary(config["webhook_path"]) and config["webhook_path"] != "" do
      :ok
    else
      {:error, ["webhook_path is required"]}
    end
  end

  @impl true
  def config_schema do
    %{"webhook_path" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :start_event
end
