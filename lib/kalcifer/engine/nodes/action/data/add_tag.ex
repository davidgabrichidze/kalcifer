defmodule Kalcifer.Engine.Nodes.Action.Data.AddTag do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Customers

  @impl true
  def execute(config, context) do
    tag = config["tag"]

    case get_customer(context) do
      nil ->
        {:completed, %{tagged: false, tag: tag, reason: "no_customer"}}

      customer ->
        case Customers.add_tag(customer, tag) do
          {:ok, _updated} ->
            {:completed, %{tagged: true, tag: tag}}

          {:error, _changeset} ->
            {:failed, :tag_failed}
        end
    end
  end

  @impl true
  def config_schema do
    %{"tag" => %{"type" => "string", "required" => true}}
  end

  @impl true
  def category, do: :action

  defp get_customer(%{"_customer" => %{"id" => id}}) when is_binary(id) do
    Customers.get_customer(id)
  end

  defp get_customer(_context), do: nil
end
