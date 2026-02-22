defmodule Kalcifer.Repo do
  use Ecto.Repo,
    otp_app: :kalcifer,
    adapter: Ecto.Adapters.Postgres
end
