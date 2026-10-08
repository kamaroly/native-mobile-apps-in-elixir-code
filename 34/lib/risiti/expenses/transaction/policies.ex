defmodule Risiti.Expenses.Transaction.Policies do
  @moduledoc false
  use Spark.Dsl.Fragment, of: Ash.Resource, authorizers: [Ash.Policy.Authorizer]

  alias Risiti.Accounts.Checks.Can

  policies do
    policy action_type(:read) do
      authorize_if Risiti.Expenses.Transaction.Checks.Visible
    end

    # `sync` runs `submit` or `update_from_phone`, each authorized in turn.
    policy action([:submit, :sync]) do
      authorize_if actor_present()
    end

    policy action([:update_from_phone, :withdraw]) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action([:approve, :reject]) do
      authorize_if {Can, permission: "transactions:approve_transactions"}
    end

    policy action(:mark_paid) do
      authorize_if {Can, permission: "transactions:mark_transactions_paid"}
    end

    policy action(:mark_exported) do
      authorize_if {Can, permission: "transactions:export_transactions"}
    end
  end
end
