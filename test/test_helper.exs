ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Kalcifer.Repo, :manual)

# Mox mocks
Mox.defmock(Kalcifer.AI.MockClient, for: Kalcifer.AI.ClientBehaviour)
