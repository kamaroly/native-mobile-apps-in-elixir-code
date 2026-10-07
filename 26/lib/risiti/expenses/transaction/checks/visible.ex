defmodule Risiti.Expenses.Transaction.Checks.Visible do
  @moduledoc """
  Which of the team's transactions the actor may see:

    * owners and whoever may list them all (accountants): every one;
    * approvers: their own, anything waiting for a decision, and approved
      claims waiting to be paid;
    * everyone else: only their own.
  """

  use Ash.Policy.FilterCheck

  alias Risiti.Accounts.Permissions

  @impl true
  def describe(_opts), do: "the transaction is one the actor may see"

  @impl true
  def filter(%{id: id, current_team: team} = actor, _context, _opts) when is_binary(team) do
    cond do
      Permissions.can?(actor, "transactions:list_all_transactions") ->
        expr(true)

      Permissions.can?(actor, "transactions:approve_transactions") or
          Permissions.can?(actor, "transactions:mark_transactions_paid") ->
        expr(user_id == ^id or status == :pending or (status == :approved and type != "expense"))

      true ->
        expr(user_id == ^id)
    end
  end

  def filter(_actor, _context, _opts), do: expr(false)
end
