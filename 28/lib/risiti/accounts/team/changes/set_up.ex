defmodule Risiti.Accounts.Team.Changes.SetUp do
  @moduledoc """
  A new team belongs to whoever made it: they become its first owner, it
  becomes their current team, and its schema gets the categories every
  team starts with, and the two default user roles.
  """

  use Ash.Resource.Change

  alias Risiti.Accounts.{Group, User, UserTeam}
  alias Risiti.Expenses.Category

  @impl true
  def change(changeset, _opts, %{actor: %User{} = actor}) do
    changeset
    |> Ash.Changeset.force_change_attribute(:owner_user_id, actor.id)
    |> Ash.Changeset.after_action(fn _changeset, team ->
      Ash.create!(UserTeam, %{user_id: actor.id, team_id: team.id, owner?: true},
        authorize?: false
      )

      Ash.update!(actor, %{team: team.domain}, action: :set_current_team, authorize?: false)
      Category.seed!(tenant: team, authorize?: false)
      Group.seed!(tenant: team, authorize?: false)
      {:ok, team}
    end)
  end

  def change(changeset, _opts, _context) do
    Ash.Changeset.add_error(changeset, "a team is made by someone: pass the actor")
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
