defmodule Kalcifer.Engine.Nodes.Action.Data.UpdateProfile do
  @moduledoc false

  use Kalcifer.Engine.NodeBehaviour

  alias Kalcifer.Customers

  @impl true
  def execute(config, context) do
    fields = config["fields"] || %{}

    if context["_dry_run"] do
      {:completed,
       %{
         dry_run: true,
         would_update: %{fields: Map.keys(fields), customer_id: context["_customer_id"]}
       }}
    else
      do_update(get_customer(context), fields)
    end
  end

  defp do_update(nil, _fields),
    do: {:completed, %{updated: false, reason: "no_customer"}}

  defp do_update(customer, fields) do
    case Customers.update_customer(customer, fields) do
      {:ok, _updated} -> {:completed, %{updated: true, fields: Map.keys(fields)}}
      {:error, _changeset} -> {:failed, :update_failed}
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
