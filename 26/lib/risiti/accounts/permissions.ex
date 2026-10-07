defmodule Risiti.Accounts.Permissions do
  @moduledoc """
  What people may do in their current team. A team's owners may do
  everything; anyone else may do what their groups grant.

  Permissions are written `"area:what"`, and listed in
  `config/permissions.exs`:

      iex> "transactions:approve_transactions" in Risiti.Accounts.Permissions.all()
      true
  """

  require Ash.Query

  alias Risiti.Accounts.{User, UserGroup, UserTeam}

  @doc "Every permission there is, as `\"area:what\"` strings."
  @spec all() :: [String.t()]
  def all do
    for {area, names} <- Application.fetch_env!(:risiti, :permissions), name <- names do
      "#{area}:#{name}"
    end
  end

  @doc "Whether `user` may do `permission` in their current team."
  @spec can?(User.t(), String.t()) :: boolean()
  def can?(%User{current_team: team} = user, permission) when is_binary(team) do
    owner?(user) or
      UserGroup
      |> Ash.Query.filter(user_id == ^user.id and has(group.permissions, ^permission))
      |> Ash.exists?(tenant: team, authorize?: false)
  end

  def can?(_user, _permission), do: false

  @doc "Whether `user` is one of the owners of their current team."
  @spec owner?(User.t()) :: boolean()
  def owner?(%User{current_team: team} = user) when is_binary(team) do
    UserTeam
    |> Ash.Query.filter(user_id == ^user.id and owner? and team.domain == ^team)
    |> Ash.exists?(authorize?: false)
  end

  def owner?(_user), do: false

  defmodule Known do
    @moduledoc "A group can only grant permissions that exist."
    use Ash.Resource.Validation

    @impl true
    def validate(changeset, opts, _context) do
      granted = Ash.Changeset.get_attribute(changeset, opts[:attribute]) || []

      case granted -- Risiti.Accounts.Permissions.all() do
        [] ->
          :ok

        unknown ->
          {:error, field: opts[:attribute], message: "unknown: #{Enum.join(unknown, ", ")}"}
      end
    end

    # The permissions are in the changeset already, so updates can check them too.
    @impl true
    def atomic(changeset, opts, context), do: validate(changeset, opts, context)
  end
end
