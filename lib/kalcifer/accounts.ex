defmodule Kalcifer.Accounts do
  @moduledoc """
  User account management — Google OAuth users linked to tenants.
  """

  import Ecto.Query

  alias Kalcifer.Accounts.User
  alias Kalcifer.Repo
  alias Kalcifer.Tenants

  @doc """
  Find or create a user from Google OAuth profile.
  If user doesn't exist, creates one with an auto-generated tenant.
  """
  def find_or_create_from_google(%{
        "sub" => google_uid,
        "email" => email,
        "name" => name,
        "picture" => avatar_url
      }) do
    case get_user_by_google_uid(google_uid) do
      %User{} = user ->
        # Update profile in case it changed
        user
        |> User.changeset(%{name: name, avatar_url: avatar_url})
        |> Repo.update()

      nil ->
        create_user_with_tenant(%{
          email: email,
          name: name,
          avatar_url: avatar_url,
          google_uid: google_uid
        })
    end
  end

  # Fallback for missing picture field
  def find_or_create_from_google(%{"sub" => _, "email" => _, "name" => _} = profile) do
    find_or_create_from_google(Map.put(profile, "picture", nil))
  end

  @doc "Get user by ID."
  def get_user(id), do: Repo.get(User, id)

  @doc "Get user by email."
  def get_user_by_email(email), do: Repo.get_by(User, email: email)

  @doc "Get user by Google UID."
  def get_user_by_google_uid(uid), do: Repo.get_by(User, google_uid: uid)

  @doc "List all users for a tenant."
  def list_users(tenant_id) do
    from(u in User, where: u.tenant_id == ^tenant_id, order_by: u.name)
    |> Repo.all()
  end

  defp create_user_with_tenant(attrs) do
    # Create a tenant for this user
    tenant_name = "#{attrs.name || attrs.email}'s workspace"
    api_key = Tenants.generate_api_key()
    api_key_hash = Tenants.hash_api_key(api_key)

    Repo.transaction(fn ->
      {:ok, tenant} =
        Tenants.create_tenant(%{name: tenant_name, api_key_hash: api_key_hash})

      {:ok, user} =
        %User{}
        |> User.changeset(Map.put(attrs, :tenant_id, tenant.id))
        |> Repo.insert()

      user
    end)
  end
end
