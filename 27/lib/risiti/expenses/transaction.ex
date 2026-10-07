defmodule Risiti.Expenses.Transaction do
  @moduledoc """
  One transaction: an expense already paid, a refund the person wants, or
  a payment they ask the team to make (`Risiti.Expenses.TransactionType`).

  Status runs `pending` → `approved` | `rejected`, and for refunds and
  payment requests `approved` → `paid`.

  Transactions arrive from phones keyed by the phone's own id for them
  (`client_id`): `Risiti.Expenses.sync_transaction/2` creates a new one or
  updates the one already sent, so a resend never makes a copy. Changing a
  decided transaction's figures sends it back for approval; a paid one
  can't be changed. Amounts are whole cents, like on the phone.

  Every change is kept, with who made it, in
  `Risiti.Expenses.Transaction.Version`.
  """

  use Ash.Resource,
    domain: Risiti.Expenses,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshPaperTrail.Resource],
    fragments: [
      Risiti.Expenses.Transaction.Attributes,
      Risiti.Expenses.Transaction.Actions,
      Risiti.Expenses.Transaction.Policies,
      Risiti.Accounts.Fragments.Multitenancies
    ]

  postgres do
    table "transactions"
    repo Risiti.Repo
  end

  paper_trail do
    primary_key_type(:uuid_v7)
    change_tracking_mode(:changes_only)
    store_action_name?(true)
    ignore_attributes([:inserted_at, :updated_at, :ocr_text])
    # Keep the history of a withdrawn transaction after it's gone.
    reference_source?(false)
    belongs_to_actor(:user, Risiti.Accounts.User, domain: Risiti.Accounts)
  end

  relationships do
    belongs_to :user, Risiti.Accounts.User do
      description "Who sent it"
      allow_nil? false
    end

    belongs_to :decided_by, Risiti.Accounts.User do
      description "Who approved or rejected it"
    end

    has_many :attachments, Risiti.Expenses.Attachment
  end

  @doc "The fields whose change sends a decided transaction back for approval."
  defdelegate figures, to: Risiti.Expenses.Transaction.Actions
end
