defmodule MobGoogle do
  @moduledoc """
  Sign in with Google on Android: shows the Google account chooser (Android
  Credential Manager) and hands back an ID token for the app's server to
  verify.

      socket = MobGoogle.sign_in(socket, server_client_id: "123-abc.apps.googleusercontent.com")

      def handle_info({:google, :result, json}, socket)
      def handle_info({:google, :error, json}, socket)

  `server_client_id` is the *Web* OAuth client ID of the server's Google
  Cloud project: the token is issued for it (its `aud`), so the server can
  check it was meant for it. The app itself must also be registered there
  as an Android client (its package name and signing certificate's SHA-1),
  or Google refuses.

  Decode the payload with `decode/1`:

    * result — `%{"id_token" => jwt, "email" => email, "name" => name | nil}`
    * error — `%{"message" => reason}`: `"cancelled"` (the person closed the
      chooser), `"no_accounts"` (no Google account on the phone),
      `"not_available"` (not Android), or what Android said.

  The message arrives at the process that called `sign_in/2` (the screen).
  """

  @doc "Shows the Google account chooser. See the module docs for the reply."
  @spec sign_in(socket, keyword()) :: socket when socket: term()
  def sign_in(socket, opts) do
    args = :json.encode(%{"server_client_id" => Keyword.fetch!(opts, :server_client_id)})

    try do
      :mob_google_nif.google_sign_in(IO.iodata_to_binary(args))
    rescue
      # No native implementation on this platform (iOS for now, or a host
      # dev build). Answer the same way a native failure would.
      error in ErlangError ->
        if error.original == :nif_not_loaded do
          send(self(), {:google, :error, ~s({"message":"not_available"})})
        else
          reraise error, __STACKTRACE__
        end
    end

    socket
  end

  @doc "Decodes the JSON payload of a `{:google, _, json}` message (JSON null becomes nil)."
  @spec decode(binary()) :: map()
  def decode(json) when is_binary(json) do
    {decoded, :ok, ""} = :json.decode(json, :ok, %{null: nil})
    decoded
  end
end
