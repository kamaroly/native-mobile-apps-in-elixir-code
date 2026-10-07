defmodule Risiti.Accounts.GoogleIdToken do
  @moduledoc """
  Checks a Google ID token (from Sign in with Google on the phone) and
  says who it's for.

  A token counts only if Google signed it (RS256, with one of the keys
  Google publishes, fetched and cached for as long as Google says), it's
  from Google, it's for one of this server's OAuth client ids (`aud`), it
  hasn't expired, and its email is verified.

      config :risiti, Risiti.Accounts.GoogleIdToken,
        client_ids: ["123-abc.apps.googleusercontent.com"]
  """

  @certs_url "https://www.googleapis.com/oauth2/v3/certs"
  @issuers ["accounts.google.com", "https://accounts.google.com"]
  @cache_key :google_certs

  @type identity :: %{sub: String.t(), email: String.t(), name: String.t() | nil}

  @spec verify(String.t()) :: {:ok, identity()} | {:error, atom()}
  def verify(token) when is_binary(token) do
    with {:ok, kid} <- key_id(token),
         {:ok, jwk} <- key(kid),
         {true, %JOSE.JWT{fields: claims}, _jws} <- JOSE.JWT.verify_strict(jwk, ["RS256"], token),
         :ok <- check(claims) do
      {:ok, %{sub: claims["sub"], email: String.downcase(claims["email"]), name: claims["name"]}}
    else
      {false, _jwt, _jws} -> {:error, :bad_signature}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify(_token), do: {:error, :malformed}

  # Which of Google's keys signed it, from the token's header.
  defp key_id(token) do
    case JOSE.JWT.peek_protected(token) do
      %JOSE.JWS{fields: %{"kid" => kid}} -> {:ok, kid}
      _ -> {:error, :malformed}
    end
  rescue
    _ -> {:error, :malformed}
  end

  defp check(claims) do
    cond do
      claims["iss"] not in @issuers -> {:error, :wrong_issuer}
      claims["aud"] not in client_ids() -> {:error, :wrong_audience}
      not is_integer(claims["exp"]) -> {:error, :malformed}
      claims["exp"] < System.os_time(:second) -> {:error, :expired}
      claims["email_verified"] not in [true, "true"] -> {:error, :email_not_verified}
      not is_binary(claims["email"]) or not is_binary(claims["sub"]) -> {:error, :malformed}
      true -> :ok
    end
  end

  # Google rotates its keys: a key id we don't know fetches them again, once.
  defp key(kid) do
    with {:ok, keys} <- keys(false) do
      case Map.fetch(keys, kid) do
        {:ok, jwk} ->
          {:ok, jwk}

        :error ->
          with {:ok, keys} <- keys(true),
               {:ok, jwk} <- Map.fetch(keys, kid) do
            {:ok, jwk}
          else
            _ -> {:error, :unknown_key}
          end
      end
    end
  end

  defp keys(refresh?) do
    case {refresh?, Cachex.get(:risiti, @cache_key)} do
      {false, {:ok, keys}} when is_map(keys) -> {:ok, keys}
      _ -> fetch_keys()
    end
  end

  defp fetch_keys do
    case Req.get(Req.new(url: @certs_url, retry: false), config()[:req_options] || []) do
      {:ok, %Req.Response{status: 200, body: %{"keys" => keys}} = response} ->
        keys = Map.new(keys, &{&1["kid"], JOSE.JWK.from_map(&1)})
        Cachex.put(:risiti, @cache_key, keys, expire: :timer.seconds(max_age(response)))
        {:ok, keys}

      _ ->
        {:error, :google_unreachable}
    end
  end

  # Google says how long to keep its keys, in Cache-Control.
  defp max_age(response) do
    with [cache_control | _] <- Req.Response.get_header(response, "cache-control"),
         [_, seconds] <- Regex.run(~r/max-age=(\d+)/, cache_control) do
      String.to_integer(seconds)
    else
      _ -> 3600
    end
  end

  defp client_ids, do: config()[:client_ids] || []

  defp config, do: Application.get_env(:risiti, __MODULE__, [])
end
