defmodule Risiti.Accounts.GoogleSignIn do
  @moduledoc """
  Signing in on the phone with a Google account. The phone hands over the
  ID token Google gave it; `Risiti.Accounts.GoogleIdToken` checks it.

  The Google account signs in the person it's linked to, or else the
  person with its verified email (and links it for next time). Anyone else
  is new: they get a sign-up token for `Risiti.Accounts.SignUp.register/2`,
  and the name Google has for them, to start the form with.
  """

  require Ash.Query

  alias Risiti.Accounts.{GoogleIdToken, SignUp, User, UserIdentity}

  @spec verify(String.t()) ::
          {:ok, User.t(), String.t()}
          | {:ok, :new, String.t(), String.t() | nil}
          | {:error, atom()}
  def verify(id_token) do
    with {:ok, google} <- GoogleIdToken.verify(id_token) do
      case linked(google.sub) || link_by_email(google) do
        %User{} = user ->
          {:ok, user, SignUp.api_token(user)}

        nil ->
          proof = %{"google" => google.sub, "email" => google.email}
          {:ok, :new, SignUp.token(proof), google.name}
      end
    end
  end

  defp linked(sub) do
    UserIdentity
    |> Ash.Query.filter(provider == "google" and uid == ^sub)
    |> Ash.Query.load(:user)
    |> Ash.read_first!(authorize?: false)
    |> case do
      %UserIdentity{user: user} -> user
      nil -> nil
    end
  end

  # Google has verified this email, so it's the same person.
  defp link_by_email(google) do
    case User |> Ash.Query.filter(email == ^google.email) |> Ash.read_first!(authorize?: false) do
      %User{} = user ->
        Ash.create!(UserIdentity, %{user_id: user.id, provider: "google", uid: google.sub},
          authorize?: false
        )

        user

      nil ->
        nil
    end
  end
end
