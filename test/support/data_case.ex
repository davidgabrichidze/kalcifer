defmodule Kalcifer.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Kalcifer.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Kalcifer.DataCase
    end
  end

  setup tags do
    Kalcifer.DataCase.setup_sandbox(tags)
    :ok
  end

  alias Ecto.Adapters.SQL.Sandbox

  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Kalcifer.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
