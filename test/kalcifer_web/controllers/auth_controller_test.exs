defmodule KalciferWeb.AuthControllerTest do
  use KalciferWeb.ConnCase, async: true

  alias KalciferWeb.AuthController

  describe "session tokens" do
    setup do
      user = %{id: Ecto.UUID.generate()}
      %{user: user}
    end

    test "generate then verify round-trips the user id", %{user: user} do
      token = AuthController.generate_session_token(user)
      assert {:ok, user_id} = AuthController.verify_session_token(token)
      assert user_id == user.id
    end

    test "a tampered signature is rejected", %{user: user} do
      token = AuthController.generate_session_token(user)
      [id, ts, _sig] = String.split(token, ".", parts: 3)
      forged = "#{id}.#{ts}.deadbeef"

      assert {:error, :invalid_signature} = AuthController.verify_session_token(forged)
    end

    test "a token for a different user id is rejected (signature covers id)", %{user: user} do
      token = AuthController.generate_session_token(user)
      [_id, ts, sig] = String.split(token, ".", parts: 3)
      swapped = "#{Ecto.UUID.generate()}.#{ts}.#{sig}"

      assert {:error, :invalid_signature} = AuthController.verify_session_token(swapped)
    end

    test "an expired token is rejected", %{user: user} do
      # Forge a token dated 31 days ago, signed correctly, via the real signer
      old_ts = (System.system_time(:second) - 31 * 24 * 3600) |> to_string()
      payload = "#{user.id}.#{old_ts}"

      sig =
        :crypto.mac(:hmac, :sha256, "test-session-secret", payload)
        |> Base.url_encode64(padding: false)

      assert {:error, :expired} = AuthController.verify_session_token("#{payload}.#{sig}")
    end

    test "malformed tokens are rejected" do
      assert {:error, :malformed} = AuthController.verify_session_token("not-a-token")
    end
  end
end
