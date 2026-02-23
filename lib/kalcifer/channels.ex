defmodule Kalcifer.Channels do
  @moduledoc false

  alias Kalcifer.Channels.Delivery
  alias Kalcifer.Repo

  def create_delivery(attrs) do
    %Delivery{}
    |> Delivery.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_delivery_status(delivery, new_status, attrs \\ %{}) do
    delivery
    |> Delivery.status_changeset(new_status, attrs)
    |> Repo.update()
  end

  def get_delivery(id) do
    Repo.get(Delivery, id)
  end
end
