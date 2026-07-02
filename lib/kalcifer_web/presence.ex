defmodule KalciferWeb.Presence do
  @moduledoc """
  Operator presence on flow topics — powers the "N operators viewing"
  indicator in the editor's live mode.
  """

  use Phoenix.Presence,
    otp_app: :kalcifer,
    pubsub_server: Kalcifer.PubSub
end
