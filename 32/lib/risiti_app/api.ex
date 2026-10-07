defmodule RisitiApp.Api do
  @moduledoc """
  The Risiti server's API (Chapter 27), from the phone's side.

  Every answer becomes one of a few results, so a screen only has to handle
  these:

    * `{:ok, body}`: it worked;
    * `{:error, :offline}`: the server couldn't be reached;
    * `{:error, :unauthorized}`: the token was refused, so sign in again;
    * `{:error, {:invalid, errors}}`: the server refused the data, with a
      field → message map, or `%{"error" => message}`;
    * `{:error, {:http, status, body}}`: anything else.

  `error_message/1` turns each into a sentence for the person.

  The server is `config :risiti_app, :api_url`, and the HTTP client is
  `config :risiti_app, :http` (`RisitiApp.Http`), so tests can stand in
  for the server.
  """

  alias RisitiApp.Accounts.Profile
  alias RisitiApp.Receipts.Photos
  alias RisitiApp.Transactions.{Attachments, Transaction}

  @doc "The server, from `config :risiti_app, :api_url`."
  @spec base_url() :: String.t()
  def base_url, do: Application.fetch_env!(:risiti_app, :api_url)

  # ── Signing in ─────────────────────────────────────────────────────────────

  @doc "Asks the server to text a sign-in code to `phone`."
  def request_code(phone), do: call(:post, "/api/auth/code", nil, {:json, %{phone: phone}})

  @doc "Exchanges the code for a token and the user, or a sign-up token."
  def verify(phone, code) do
    case call(:post, "/api/auth/verify", nil, {:json, %{phone: phone, code: code}}) do
      # Here a 401 means a wrong code, not a lapsed sign-in.
      {:error, :unauthorized} ->
        {:error, {:invalid, %{"error" => "That code is wrong or has expired"}}}

      other ->
        other
    end
  end

  @doc "Signs in with the ID token Google gave the phone."
  def google(id_token) do
    case call(:post, "/api/auth/google", nil, {:json, %{id_token: id_token}}) do
      {:error, :unauthorized} ->
        {:error, {:invalid, %{"error" => "That Google sign-in didn't work. Try again."}}}

      other ->
        other
    end
  end

  @doc "Someone new: their name, and a team name for a business (blank for a personal book)."
  def register(signup_token, name, team_name) do
    body = %{signup_token: signup_token, name: name, team_name: team_name}
    call(:post, "/api/auth/register", nil, {:json, body})
  end

  @doc "Who the server says the person is now, and what they may do."
  def me(profile), do: call(:get, "/api/me", profile)

  # ── The person's own transactions ──────────────────────────────────────────

  # Sent as they are; nil is left out.
  @fields [
    :type,
    :pay_to,
    :date,
    :vendor,
    :amount_cents,
    :category,
    :source,
    :qr_content,
    :seller_pin,
    :branch_id,
    :invoice_number,
    :verify_url,
    :verified_at,
    :ocr_text
  ]

  # Sent even when blank, so clearing one here clears it on the server too
  # (a refund taken back no longer names a phone to pay).
  @clearable [:description, :method, :phone, :till_number, :paybill_number, :account_number]

  @doc """
  Sends a transaction, keyed by its `client_id`, so sending it again
  updates it. The photo goes along until the server has it
  (`photo_pushed`), and so do the attachments it hasn't got yet (no
  `remote_id`).
  """
  def put_transaction(%Profile{} = profile, %Transaction{} = transaction) do
    fields =
      Enum.flat_map(@fields, fn key ->
        case Map.fetch!(transaction, key) do
          nil -> []
          value -> [{Atom.to_string(key), field_value(value)}]
        end
      end) ++
        Enum.map(@clearable, fn key ->
          {Atom.to_string(key), field_value(Map.fetch!(transaction, key) || "")}
        end)

    photo =
      with false <- transaction.photo_pushed,
           path when is_binary(path) <- Photos.path(transaction.photo_path),
           true <- File.regular?(path) do
        [{"photo", {:file, path, Path.basename(path), "image/jpeg"}}]
      else
        _ -> []
      end

    files =
      for attachment <- transaction.attachments,
          is_nil(attachment.remote_id),
          path = Attachments.path(attachment.file_name),
          File.regular?(path) do
        {"attachments[]", {:file, path, attachment.name, attachment.content_type}}
      end

    call(
      :put,
      "/api/transactions/#{URI.encode(transaction.client_id)}",
      profile,
      {:multipart, fields ++ photo ++ files}
    )
  end

  @doc "Tells the server a transaction was deleted here. It keeps one already decided."
  def delete_transaction(%Profile{} = profile, client_id),
    do: call(:delete, "/api/transactions/#{URI.encode(client_id)}", profile)

  @doc "The person's own transactions, decisions and all."
  def list_transactions(profile), do: call(:get, "/api/transactions", profile)

  @doc "Downloads a photo or attachment (`path` like /api/attachments/ID) to `dest`."
  def download(profile, path, dest) do
    case call(:get, path, profile) do
      {:ok, body} when is_binary(body) -> File.write(dest, body)
      {:ok, _not_a_file} -> {:error, :not_a_file}
      error -> error
    end
  end

  # ── Push notifications and approvals (Chapter 32) ──────────────────────────

  @doc "Tells the server this phone's push token, so it can notify the person."
  def register_device(profile, platform, token),
    do: call(:put, "/api/devices", profile, {:json, %{platform: platform, token: token}})

  @doc "Asks the server to stop pushing to this phone."
  def forget_device(profile, token),
    do: call(:delete, "/api/devices/#{URI.encode_www_form(token)}", profile)

  @doc "What waits for a decision, and approved claims waiting to be paid."
  def approvals(profile), do: call(:get, "/api/approvals", profile)

  @doc ~s(`decision` is "approve", "reject" \(with a note\) or "pay".)
  def decide(profile, id, decision, note),
    do: call(:post, "/api/approvals/#{id}/#{decision}", profile, {:json, %{note: note}})

  defp field_value(%Date{} = date), do: Date.to_iso8601(date)
  defp field_value(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp field_value(value), do: to_string(value)

  # ── Plumbing ───────────────────────────────────────────────────────────────

  defp call(method, path, profile, body \\ nil) do
    headers =
      case profile do
        %Profile{api_token: token} when is_binary(token) ->
          [{"authorization", "Bearer " <> token}]

        _ ->
          []
      end

    method
    |> http().request(base_url() <> path,
      headers: [{"accept", "application/json"} | headers],
      body: body
    )
    |> result()
  end

  defp result({:ok, status, body}) when status in 200..299, do: {:ok, body}
  defp result({:ok, 401, _body}), do: {:error, :unauthorized}
  defp result({:ok, 422, %{"errors" => errors}}), do: {:error, {:invalid, errors}}

  defp result({:ok, status, %{"error" => _} = body}) when status in 400..499,
    do: {:error, {:invalid, body}}

  defp result({:ok, status, body}), do: {:error, {:http, status, body}}
  defp result({:error, _reason}), do: {:error, :offline}

  defp http, do: Application.get_env(:risiti_app, :http, RisitiApp.Http)

  # ── Messages ───────────────────────────────────────────────────────────────

  @doc """
  The sentence to show for an error from this module.

      iex> RisitiApp.Api.error_message({:invalid, %{"till_number" => "must be 5 to 7 digits"}})
      "Till number must be 5 to 7 digits"
  """
  @spec error_message(term()) :: String.t()
  def error_message(:offline), do: "Can't reach the server. Check your internet connection."
  def error_message(:unauthorized), do: "Please sign in again."
  def error_message({:invalid, %{"error" => message}}), do: message

  def error_message({:invalid, errors}) when is_map(errors),
    do: Enum.map_join(errors, ". ", fn {field, message} -> "#{humanize(field)} #{message}" end)

  def error_message(_error), do: "Something went wrong on the server. Try again."

  defp humanize(field),
    do: field |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
