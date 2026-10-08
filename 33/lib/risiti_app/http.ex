defmodule RisitiApp.Http do
  @moduledoc """
  A small HTTP client over OTP's `:httpc`, which ships with the app's Erlang
  runtime: no extra dependencies on the phone.

  It deals with the two things a phone needs that a server doesn't:

    * TLS verifies against the CA bundle `RisitiApp.App` loads at start
      (Android gives the BEAM no trust store of its own; see `Mob.Certs`);
    * host names resolve through the phone's resolver (`Mob.DNS.resolve/1`),
      because the BEAM's own lookup can fail on a real phone.

  Only GET for now. Part IV adds request bodies, for the server's API.
  """

  @timeout 20_000

  @doc "Fetches `url`. Returns `{:ok, status, body}` or `{:error, reason}`."
  def get(url, opts \\ []) do
    with :ok <- start(),
         :ok <- check_tls(url) do
      resolve_host(url)

      timeout = Keyword.get(opts, :timeout, @timeout)
      request = {String.to_charlist(url), [{~c"user-agent", ~c"RisitiApp"}]}
      http_opts = [timeout: timeout, connect_timeout: timeout, ssl: ssl_opts()]

      case :httpc.request(:get, request, http_opts, body_format: :binary) do
        {:ok, {{_, status, _}, _headers, body}} -> {:ok, status, body}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp start do
    with {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl) do
      :ok
    end
  end

  # Without a trust store, refuse HTTPS rather than connect unverified.
  defp check_tls("https://" <> _),
    do: if(Mob.Certs.loaded?(), do: :ok, else: {:error, :no_cacerts})

  defp check_tls(_url), do: :ok

  # Seeds the BEAM's host table from the phone's own resolver. Off the phone
  # (no NIF) this fails harmlessly and the normal lookup is used. IP
  # addresses need no lookup.
  defp resolve_host(url) do
    with %URI{host: host} when is_binary(host) <- URI.parse(url),
         {:error, _} <- :inet.parse_address(String.to_charlist(host)) do
      Mob.DNS.resolve(host)
    end
  end

  defp ssl_opts do
    if Mob.Certs.loaded?() do
      [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 4,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    else
      []
    end
  end
end
