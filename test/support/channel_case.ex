defmodule KalciferWeb.ChannelCase do
  @moduledoc """
  Test case for Phoenix channel tests: sets up the SQL sandbox and
  imports channel test helpers with the app endpoint.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import KalciferWeb.ChannelCase
      import Phoenix.ChannelTest

      @endpoint KalciferWeb.Endpoint
    end
  end

  setup tags do
    Kalcifer.DataCase.setup_sandbox(tags)
    :ok
  end
end
