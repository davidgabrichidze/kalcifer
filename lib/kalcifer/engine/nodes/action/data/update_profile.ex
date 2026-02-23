defmodule Kalcifer.Engine.Nodes.Action.Data.UpdateProfile do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Customers

  @impl true
  def execute(config, context) do
    fields = config["fields"] || %{}

    case get_customer(context) do
      nil ->
        {:completed, %{updated: false, reason: "no_customer"}}

      customer ->
        case Customers.update_customer(customer, fields) do
          {:ok, _updated} ->
            {:completed, %{updated: true, fields: Map.keys(fields)}}

          {:error, _changeset} ->
            {:failed, :update_failed}
        end
    end
  end

  @impl true
  def config_schema do
    %{"fields" => %{"type" => "map", "required" => true}}
  end

  @impl true
  def category, do: :action

  defp get_customer(%{"_customer" => %{"id" => id}}) when is_binary(id) do
    Customers.get_customer(id)
  end

  defp get_customer(_context), do: nil
end
