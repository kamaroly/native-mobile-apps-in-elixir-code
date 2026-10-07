defmodule RisitiApp.Accounts do
  @moduledoc """
  Connecting this phone's book to the Risiti server.

  The book works without the server. Signing in (`RisitiApp.Screens.PhoneScreen`)
  connects it: the phone keeps the server's API token and what the server
  says the person may do, and `RisitiApp.Sync` (Chapter 31) sends the book
  to their team.

  One phone, one book: the real Risiti keeps a separate book per phone
  number, so several people can share a phone. The book's version keeps
  one, and won't hand it to someone else's account.
  """

  import Ecto.Query, only: [from: 2]

  alias RisitiApp.Accounts.Profile
  alias RisitiApp.Repo
  alias RisitiApp.Transactions.Transaction

  @doc "Who this phone's book belongs to, or nil if nobody has signed in yet."
  @spec current_profile() :: Profile.t() | nil
  def current_profile, do: Repo.one(from p in Profile, order_by: p.id, limit: 1)

  @doc """
  After signing in: keeps the server's token and user for this phone's
  book, under the person's phone number.

  A book that was connected to one account, and has transactions, isn't
  handed to another: `{:error, :another_book}`.
  """
  @spec connect(String.t(), map()) ::
          {:ok, Profile.t()} | {:error, :another_book | Ecto.Changeset.t()}
  def connect(phone, %{"token" => token, "user" => user}) do
    profile = current_profile() || %Profile{}

    if someone_elses?(profile, user["id"]) do
      {:error, :another_book}
    else
      profile
      |> Profile.server_changeset(
        Map.merge(server_attrs(user), %{phone: phone, api_token: token})
      )
      |> Repo.insert_or_update()
    end
  end

  @doc "Stores what the server says about the person now (from GET /api/me)."
  @spec apply_server_user(Profile.t(), map()) :: {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def apply_server_user(%Profile{} = profile, user) do
    profile |> Profile.server_changeset(server_attrs(user)) |> Repo.update()
  end

  @doc "Stops talking to the server. The book, and whose it is, stay."
  @spec disconnect(Profile.t()) :: {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def disconnect(%Profile{} = profile) do
    profile
    |> Profile.server_changeset(%{
      api_token: nil,
      team: nil,
      team_kind: nil,
      team_name: nil,
      can_approve: false,
      can_mark_paid: false,
      can_list_all: false,
      can_export: false
    })
    |> Repo.update()
  end

  defp server_attrs(user) do
    permissions = user["permissions"] || %{}

    %{
      name: user["name"],
      remote_user_id: user["id"],
      team: user["team"],
      team_kind: user["team_kind"],
      team_name: user["team_name"],
      can_approve: permissions["approve"] == true,
      can_mark_paid: permissions["mark_paid"] == true,
      can_list_all: permissions["list_all"] == true,
      can_export: permissions["export"] == true
    }
  end

  defp someone_elses?(%Profile{remote_user_id: nil}, _user_id), do: false
  defp someone_elses?(%Profile{remote_user_id: same}, same), do: false
  defp someone_elses?(_profile, _user_id), do: Repo.exists?(Transaction)
end
