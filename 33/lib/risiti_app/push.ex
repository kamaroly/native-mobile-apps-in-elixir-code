defmodule RisitiApp.Push do
  @moduledoc """
  Push notifications from the team's server: `mob_notify` on the phone,
  `mob_push` on the server (Chapter 28).

  Once a business book is connected, the home screen asks for the
  notification permission and registers for pushes. Firebase gives the
  phone a token; it goes to the server, which pushes when someone else
  acts. A push also makes the phone sync, so its lists catch up.

  The token is kept in `Mob.State`, with what was last sent, so the server
  is only told again when something changed, and disconnecting can tell it
  to stop.
  """

  alias RisitiApp.Accounts.Profile
  alias RisitiApp.Api

  @token_key :push_token
  # {sign-in token, push token} last sent to the server.
  @sent_key :push_token_sent

  @doc "Whether pushes are set up for this build (`config :risiti_app, :push`)."
  def enabled?, do: Application.get_env(:risiti_app, :push, false)

  @doc "Keeps the token Firebase gave this phone."
  @spec remember(:ios | :android, String.t()) :: :ok
  def remember(platform, token), do: put(@token_key, {platform, token})

  @doc "True when there's a token the server hasn't been given for this sign-in."
  @spec pending?(Profile.t()) :: boolean()
  def pending?(%Profile{api_token: api_token}) do
    case get(@token_key) do
      {_platform, token} -> get(@sent_key) != {api_token, token}
      nil -> false
    end
  end

  @doc "Sends the token to the server, unless it already has it. Runs off the screen."
  @spec register(Profile.t()) :: :ok | {:error, term()}
  def register(%Profile{} = profile) do
    with {platform, token} <- get(@token_key),
         true <- pending?(profile),
         {:ok, _} <- Api.register_device(profile, platform, token) do
      put(@sent_key, {profile.api_token, token})
    else
      false -> :ok
      nil -> :ok
      {:error, _} = error -> error
    end
  end

  @doc "Asks the server to stop pushing to this phone (before disconnecting)."
  @spec forget(Profile.t()) :: :ok | {:error, term()}
  def forget(%Profile{} = profile) do
    put(@sent_key, nil)

    case get(@token_key) do
      {_platform, token} -> with {:ok, _} <- Api.forget_device(profile, token), do: :ok
      nil -> :ok
    end
  end

  @doc """
  The screen a push is about: `:approvals` for something to decide,
  `:receipts` for news about the person's own.

      iex> RisitiApp.Push.screen(%{data: %{screen: "approvals"}})
      :approvals

      iex> RisitiApp.Push.screen(%{data: %{screen: "transactions"}})
      :receipts
  """
  @spec screen(map()) :: :approvals | :receipts
  def screen(%{data: %{screen: "approvals"}}), do: :approvals
  def screen(_notification), do: :receipts

  @doc """
  What to say for a push that arrived while the app was open.

      iex> RisitiApp.Push.notice(%{title: "Your refund was approved", body: "Java House · Ksh 1,650"})
      "Your refund was approved: Java House · Ksh 1,650"
  """
  def notice(%{title: title, body: body})
      when is_binary(title) and is_binary(body) and body != "",
      do: "#{title}: #{body}"

  def notice(%{title: title}) when is_binary(title), do: title
  def notice(_notification), do: "Updated from your team"

  defp get(key), do: Mob.State.get(key, nil)
  defp put(key, value), do: Mob.State.put(key, value)
end
