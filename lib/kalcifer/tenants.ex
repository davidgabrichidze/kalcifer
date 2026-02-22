defmodule Kalcifer.Tenants do
  @moduledoc false

  alias Kalcifer.Repo
  alias Kalcifer.Tenants.Tenant

  def get_tenant_by_api_key_hash(hash) do
    Repo.get_by(Tenant, api_key_hash: hash)
  end

  def create_tenant(attrs) do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert()
  end

  def hash_api_key(raw_key) do
    :crypto.hash(:sha256, raw_key) |> Base.encode16(case: :lower)
  end
end
