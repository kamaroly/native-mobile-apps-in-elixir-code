defmodule RisitiApp.Http do
  @moduledoc """
  A small HTTP client over OTP's `:httpc`, which ships with the app's Erlang
  runtime: no extra dependencies on the phone.

  It deals with the two things a phone needs that a server doesn't:

    * TLS verifies against the CA bundle `RisitiApp.App` loads at start
      (Android gives the BEAM no trust store of its own; see `Mob.Certs`);
    * host names resolve through the phone's resolver (`Mob.DNS.resolve/1`),
      because the BEAM's own lookup can fail on a real phone.

  Bodies: `{:json, term}` or `{:multipart, parts}`, where each part is
  `{name, value}` or `{name, {:file, path, filename, content_type}}`.
  JSON responses are decoded.
  """

  @timeout 20_000

  @type body :: nil | {:json, term()} | {:multipart, [{String.t(), term()}]}
  @type response :: {:ok, pos_integer(), term()} | {:error, term()}

  @doc "Sends a request. Returns the status and the body (decoded when JSON)."
  @spec request(atom(), String.t(), keyword()) :: response()
  def request(method, url, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])

    with :ok <- start(),
         :ok <- check_tls(url),
         {:ok, content_type, payload} <- encode(Keyword.get(opts, :body)) do
      resolve_host(url)

      send_request(
        method,
        url,
        headers,
        content_type,
        payload,
        Keyword.get(opts, :timeout, @timeout)
      )
    end
  end

  @spec get(String.t(), keyword()) :: response()
  def get(url, opts \\ []), do: request(:get, url, opts)

  defp send_request(method, url, headers, content_type, payload, timeout) do
    headers = [{"user-agent", "RisitiApp"} | headers] |> Enum.map(&charlist_header/1)

    request =
      case payload do
        nil -> {String.to_charlist(url), headers}
        body -> {String.to_charlist(url), headers, String.to_charlist(content_type), body}
      end

    http_opts = [timeout: timeout, connect_timeout: timeout, ssl: ssl_opts()]

    case :httpc.request(method, request, http_opts, body_format: :binary) do
      {:ok, {{_, status, _}, resp_headers, body}} -> {:ok, status, decode(resp_headers, body)}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Bodies ─────────────────────────────────────────────────────────────────

  defp encode(nil), do: {:ok, nil, nil}
  defp encode({:json, term}), do: {:ok, "application/json", JSON.encode!(term)}

  defp encode({:multipart, parts}) do
    boundary = "----risitiapp" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)

    with {:ok, encoded} <- encode_parts(parts, boundary) do
      body = IO.iodata_to_binary([encoded, "--", boundary, "--\r\n"])
      {:ok, "multipart/form-data; boundary=" <> boundary, body}
    end
  end

  defp encode_parts(parts, boundary) do
    Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, acc} ->
      case encode_part(part, boundary) do
        {:ok, encoded} -> {:cont, {:ok, [acc, encoded]}}
        error -> {:halt, error}
      end
    end)
  end

  defp encode_part({name, {:file, path, filename, content_type}}, boundary) do
    with {:ok, data} <- File.read(path) do
      {:ok,
       [
         "--",
         boundary,
         "\r\n",
         ~s(Content-Disposition: form-data; name="#{name}"; filename="#{escape(filename)}"\r\n),
         "Content-Type: ",
         content_type,
         "\r\n\r\n",
         data,
         "\r\n"
       ]}
    end
  end

  defp encode_part({name, value}, boundary) do
    {:ok,
     [
       "--",
       boundary,
       "\r\n",
       ~s(Content-Disposition: form-data; name="#{name}"\r\n\r\n),
       to_string(value),
       "\r\n"
     ]}
  end

  defp escape(filename), do: String.replace(filename, ~s("), "'")

  defp decode(headers, body) do
    json? =
      Enum.any?(headers, fn {key, value} ->
        String.downcase(to_string(key)) == "content-type" and
          String.contains?(to_string(value), "json")
      end)

    if json? and body != "" do
      case JSON.decode(body) do
        {:ok, decoded} -> decoded
        {:error, _} -> body
      end
    else
      body
    end
  end

  # ── Transport ──────────────────────────────────────────────────────────────

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

  defp charlist_header({key, value}), do: {String.to_charlist(key), String.to_charlist(value)}
end
