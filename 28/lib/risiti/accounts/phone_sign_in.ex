defmodule Risiti.Accounts.PhoneSignIn do
  @moduledoc """
  Signing in on the phone with a 6-digit code sent by SMS.

  A number already on Risiti signs straight in, with an API token. A new
  number, once its code is right, gets a short-lived sign-up token instead,
  for `Risiti.Accounts.SignUp.register/2`.

  Codes cost money to send, so at most 5 an hour go to one number and 10
  an hour to one address. Each lasts 10 minutes and allows 5 guesses.
  """

  require Ash.Query

  alias Risiti.Accounts.{Phone, PhoneCode, SignUp, User}

  @ttl_minutes 10
  @max_attempts 5
  @max_per_hour 5
  @max_per_ip_hour 10

  @doc """
  Queues an SMS with a new code to `raw_phone` (`Risiti.SMSWorker`). `ip`
  is the client's address, for the limits.
  """
  @spec request_code(String.t(), String.t() | nil) ::
          :ok | {:error, :invalid_phone | :too_many_requests | term()}
  def request_code(raw_phone, ip \\ nil) do
    with {:ok, phone} <- normalize(raw_phone),
         :ok <- under_rate_limit(phone, ip) do
      code = new_code()
      message = "Your Risiti code is #{code}. It expires in #{@ttl_minutes} minutes."

      # The code and its SMS job are saved together, or not at all.
      Ash.transact(PhoneCode, fn ->
        with {:ok, _job} <- Risiti.SMSWorker.enqueue(phone, message) do
          Ash.create!(
            PhoneCode,
            %{
              phone: phone,
              ip: ip,
              code_hash: hash(phone, code),
              expires_at: DateTime.add(DateTime.utc_now(), @ttl_minutes, :minute)
            },
            action: :issue,
            authorize?: false
          )
        end
      end)
      |> case do
        {:ok, _phone_code} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Checks `code`. A known number gets its user and an API token; a new one
  gets a sign-up token for `Risiti.Accounts.SignUp.register/2`.
  """
  @spec verify(String.t(), String.t()) ::
          {:ok, User.t(), String.t()}
          | {:ok, :new, String.t()}
          | {:error, :invalid_phone | :invalid_code}
  def verify(raw_phone, code) do
    with {:ok, phone} <- normalize(raw_phone),
         {:ok, phone_code} <- latest_code(phone),
         :ok <- check(phone_code, phone, code) do
      Ash.update!(phone_code, %{}, action: :use, authorize?: false)

      case user(phone) do
        {:ok, user} -> {:ok, user, SignUp.api_token(user)}
        :none -> {:ok, :new, SignUp.token(%{"phone" => phone})}
      end
    end
  end

  defp normalize(raw) do
    case Phone.normalize(raw || "") do
      {:ok, phone} -> {:ok, phone}
      :error -> {:error, :invalid_phone}
    end
  end

  defp user(phone) do
    case User |> Ash.Query.filter(phone == ^phone) |> Ash.read_one(authorize?: false) do
      {:ok, %User{} = user} -> {:ok, user}
      _ -> :none
    end
  end

  defp under_rate_limit(phone, ip) do
    hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)
    recent = Ash.Query.filter(PhoneCode, inserted_at > ^hour_ago)

    by_phone = recent |> Ash.Query.filter(phone == ^phone) |> Ash.count!(authorize?: false)

    by_ip =
      if ip,
        do: recent |> Ash.Query.filter(ip == ^ip) |> Ash.count!(authorize?: false),
        else: 0

    if by_phone < @max_per_hour and by_ip < @max_per_ip_hour,
      do: :ok,
      else: {:error, :too_many_requests}
  end

  # Only the newest unused, unexpired code counts.
  defp latest_code(phone) do
    now = DateTime.utc_now()

    PhoneCode
    |> Ash.Query.filter(phone == ^phone and is_nil(used_at) and expires_at > ^now)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %PhoneCode{} = phone_code} -> {:ok, phone_code}
      _ -> {:error, :invalid_code}
    end
  end

  defp check(%PhoneCode{attempts: attempts}, _phone, _code) when attempts >= @max_attempts,
    do: {:error, :invalid_code}

  defp check(phone_code, phone, code) do
    if Plug.Crypto.secure_compare(hash(phone, to_string(code)), phone_code.code_hash) do
      :ok
    else
      Ash.update!(phone_code, %{}, action: :record_attempt, authorize?: false)
      {:error, :invalid_code}
    end
  end

  defp new_code, do: 100_000..999_999 |> Enum.random() |> Integer.to_string()

  # Keyed with the app's secret, so a leaked table doesn't give codes away.
  defp hash(phone, code) do
    :crypto.mac(:hmac, :sha256, secret(), phone <> ":" <> code) |> Base.encode16(case: :lower)
  end

  defp secret, do: Application.fetch_env!(:risiti, RisitiWeb.Endpoint)[:secret_key_base]
end
