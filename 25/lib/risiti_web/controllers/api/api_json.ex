defmodule RisitiWeb.Api.JSON do
  @moduledoc """
  The JSON the phone reads. Amounts are integer cents, dates ISO 8601,
  types and statuses lowercase strings: the same as on the phone.
  """

  alias Risiti.Accounts.Permissions

  # The phone's names for the permissions it acts on.
  @permissions %{
    approve: "transactions:approve_transactions",
    mark_paid: "transactions:mark_transactions_paid",
    list_all: "transactions:list_all_transactions",
    export: "transactions:export_transactions"
  }

  @doc "The signed-in person, their current team, and what they may do in it."
  def user(user) do
    team = user.current_team && Risiti.Accounts.team_for_tenant!(user.current_team)

    %{
      id: user.id,
      name: user.name,
      phone: user.phone,
      email: user.email && to_string(user.email),
      team: user.current_team,
      team_name: team && team.name,
      # "personal" (just them: no approvals, no claims) or "business".
      team_kind: team && team.kind,
      permissions:
        Map.new(@permissions, fn {key, name} -> {key, Permissions.can?(user, name)} end)
    }
  end

  @doc "Ash's validation errors as `%{field => message}`."
  def errors(%Ash.Error.Invalid{errors: errors}) do
    Map.new(errors, fn error -> {Map.get(error, :field) || :base, Exception.message(error)} end)
  end

  def errors(other), do: %{base: inspect(other)}
end
