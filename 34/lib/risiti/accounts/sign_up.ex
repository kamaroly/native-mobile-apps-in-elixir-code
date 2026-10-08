defmodule Risiti.Accounts.SignUp do
  @moduledoc """
  Signing up on the phone, however the person proved who they are.

  `Risiti.Accounts.PhoneSignIn` (an SMS code) and
  `Risiti.Accounts.GoogleSignIn` (a Google ID token) hand someone new a
  short-lived sign-up token saying what was proved: a phone number, or a
  Google account. `register/2` turns it into a person and their first
  team: a free personal book, or a business that they own.
  """

  require Ash.Query

  alias Risiti.Accounts.{User, UserIdentity}

  @salt "mobile sign-up"
  @max_age_minutes 30

  @typedoc "What was proved: a phone number, or a Google account."
  @type proof :: %{String.t() => term()}

  @doc "A sign-up token for `proof`, good for #{@max_age_minutes} minutes."
  @spec token(proof()) :: String.t()
  def token(proof), do: Plug.Crypto.sign(secret(), @salt, proof)

  @doc """
  Creates the person behind a sign-up token, with their team, and signs
  them in. A blank `"team_name"` means just them: a personal book. Someone
  who signed up already (a second tap, another phone) just signs in.
  """
  @spec register(String.t(), map()) ::
          {:ok, User.t(), String.t()} | {:error, :expired | term()}
  def register(signup_token, attrs) do
    with {:ok, proof} <- verify(signup_token) do
      case existing(proof) do
        %User{} = user -> {:ok, user, api_token(user)}
        nil -> create(proof, attrs)
      end
    end
  end

  @doc "An API token for `user`: what the phone sends as `Authorization: Bearer ...`."
  @spec api_token(User.t()) :: String.t()
  def api_token(user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    token
  end

  defp verify(token) when is_binary(token) do
    case Plug.Crypto.verify(secret(), @salt, token, max_age: @max_age_minutes * 60) do
      {:ok, proof} -> {:ok, proof}
      {:error, _} -> {:error, :expired}
    end
  end

  defp verify(_token), do: {:error, :expired}

  defp existing(%{"phone" => phone}),
    do: User |> Ash.Query.filter(phone == ^phone) |> Ash.read_first!(authorize?: false)

  defp existing(%{"google" => sub}) do
    UserIdentity
    |> Ash.Query.filter(provider == "google" and uid == ^sub)
    |> Ash.Query.load(:user)
    |> Ash.read_first!(authorize?: false)
    |> case do
      %UserIdentity{user: user} -> user
      nil -> nil
    end
  end

  defp create(proof, attrs) do
    name = attrs |> Map.get("name") |> to_string() |> String.trim()
    team_name = attrs |> Map.get("team_name") |> to_string() |> String.trim()

    Ash.transact(User, fn ->
      with {:ok, user} <- create_user(proof, name),
           {:ok, _team} <- create_team(user, team_name) do
        # The new team is their current one now.
        Ash.get!(User, user.id, authorize?: false)
      end
    end)
    |> case do
      {:ok, user} -> {:ok, user, api_token(user)}
      {:error, error} -> {:error, error}
    end
  end

  defp create_user(%{"phone" => phone}, name) do
    Ash.create(User, %{phone: phone, name: name},
      action: :register_with_phone,
      authorize?: false
    )
  end

  defp create_user(%{"google" => sub, "email" => email}, name) do
    with {:ok, user} <-
           Ash.create(User, %{email: email, name: name},
             action: :register_with_google,
             authorize?: false
           ),
         {:ok, _identity} <-
           Ash.create(UserIdentity, %{user_id: user.id, provider: "google", uid: sub},
             authorize?: false
           ) do
      {:ok, user}
    end
  end

  defp create_team(user, "" = _just_me),
    do: Risiti.Accounts.create_team("Personal", :personal, actor: user)

  defp create_team(user, team_name),
    do: Risiti.Accounts.create_team(team_name, :business, actor: user)

  defp secret, do: Application.fetch_env!(:risiti, RisitiWeb.Endpoint)[:secret_key_base]
end
