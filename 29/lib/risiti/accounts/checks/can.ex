defmodule Risiti.Accounts.Checks.Can do
  @moduledoc """
  A policy check: passes when the actor holds `permission` in their
  current team (see `Risiti.Accounts.Permissions`).

      authorize_if {Risiti.Accounts.Checks.Can, permission: "transactions:approve_transactions"}
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts), do: "actor has the #{opts[:permission]} permission"

  @impl true
  def match?(actor, _context, opts),
    do: Risiti.Accounts.Permissions.can?(actor, Keyword.fetch!(opts, :permission))
end
