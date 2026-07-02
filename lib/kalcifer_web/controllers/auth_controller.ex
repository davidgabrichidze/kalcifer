defmodule KalciferWeb.AuthController do
  @moduledoc """
  Handles Google OAuth authentication.

  Flow:
  1. Frontend gets Google ID token (via Google Sign-In button)
  2. Frontend POSTs token to /api/v1/auth/google
  3. Backend verifies token with Google, extracts profile
  4. Backend finds/creates user, generates session token (JWT)
  5. Frontend stores JWT, sends as Bearer token on subsequent requests
  """

  use KalciferWeb, :controller

  alias Kalcifer.Accounts

  require Logger

  @google_token_info_url "https://oauth2.googleapis.com/tokeninfo"

  @doc """
  POST /api/v1/auth/google

  Accepts: {"id_token": "..."}
  Returns: {"user": {...}, "token": "...", "tenant_id": "..."}
  """
  def google(conn, %{"id_token" => id_token}) do
    case verify_google_token(id_token) do
      {:ok, profile} ->
        case Accounts.find_or_create_from_google(profile) do
          {:ok, user} ->
            token = generate_session_token(user)

            json(conn, %{
              user: %{
                id: user.id,
                email: user.email,
                name: user.name,
                avatar_url: user.avatar_url
              },
              token: token,
              tenant_id: user.tenant_id
            })

          {:error, reason} ->
            Logger.warning("OAuth user creation failed: #{inspect(reason)}")

            conn
            |> put_status(422)
            |> json(%{error: "Failed to create account"})
        end

      {:error, reason} ->
        Logger.warning("Google token verification failed: #{reason}")

        conn
        |> put_status(401)
        |> json(%{error: "Invalid Google token"})
    end
  end

  def google(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Missing id_token"})
  end

  @doc """
  GET /api/v1/auth/me

  Returns the current authenticated user's profile.
  """
  def me(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_status(401)
        |> json(%{error: "Not authenticated"})

      user ->
        json(conn, %{
          user: %{
            id: user.id,
            email: user.email,
            name: user.name,
            avatar_url: user.avatar_url,
            tenant_id: user.tenant_id
          }
        })
    end
  end

  # ── Token verification ────────────────────────────────────

  defp verify_google_token(id_token) do
    # Req verifies the server's TLS certificate by default — critical here,
    # since an unverified response could forge email_verified/sub/email and
    # let an on-path attacker mint a session for any account.
    case Req.get(@google_token_info_url,
           params: [id_token: id_token],
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: %{"email_verified" => verified} = claims}}
      when verified in [true, "true"] ->
        {:ok,
         %{
           "sub" => claims["sub"],
           "email" => claims["email"],
           "name" => claims["name"] || claims["email"],
           "picture" => claims["picture"]
         }}

      {:ok, %{status: 200}} ->
        {:error, "Email not verified"}

      {:ok, %{status: status}} ->
        {:error, "Google returned #{status}"}

      {:error, reason} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  # ── Session token (simple HMAC-based) ─────────────────────

  @doc """
  Generate a session token for a user.
  Format: user_id.timestamp.signature
  """
  def generate_session_token(user) do
    timestamp = System.system_time(:second) |> to_string()
    payload = "#{user.id}.#{timestamp}"
    signature = sign(payload)
    "#{payload}.#{signature}"
  end

  @doc """
  Verify a session token and return the user_id.
  Token expires after 30 days.
  """
  def verify_session_token(token) do
    case String.split(token, ".", parts: 3) do
      [user_id, timestamp_str, signature] ->
        payload = "#{user_id}.#{timestamp_str}"

        if Plug.Crypto.secure_compare(sign(payload), signature) do
          case Integer.parse(timestamp_str) do
            {timestamp, _} ->
              now = System.system_time(:second)
              max_age = 30 * 24 * 3600

              if now - timestamp < max_age do
                {:ok, user_id}
              else
                {:error, :expired}
              end

            _ ->
              {:error, :invalid}
          end
        else
          {:error, :invalid_signature}
        end

      _ ->
        {:error, :malformed}
    end
  end

  defp sign(payload) do
    :crypto.mac(:hmac, :sha256, session_secret(), payload)
    |> Base.url_encode64(padding: false)
  end

  # A fixed literal fallback would make every unconfigured deployment share a
  # public signing key, so tokens would be trivially forgeable. Fail loudly
  # instead; dev/test set the secret in config.
  defp session_secret do
    case Application.get_env(:kalcifer, :auth_session_secret) do
      secret when is_binary(secret) and secret != "" ->
        secret

      _ ->
        raise "auth_session_secret is not configured (set AUTH_SESSION_SECRET)"
    end
  end
end
