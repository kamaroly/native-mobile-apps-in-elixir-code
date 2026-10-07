defmodule Risiti.Expenses.Transaction.Changes.SetPayTo do
  @moduledoc """
  Who a transaction pays follows from its type: nobody for an expense
  (already paid), the person for a refund, and for a payment request a
  supplier unless the person asked for an advance to themselves.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    pay_to =
      case Ash.Changeset.get_attribute(changeset, :type) do
        "expense" -> nil
        "refund" -> :self
        "payment_request" -> Ash.Changeset.get_attribute(changeset, :pay_to) || :supplier
        _other -> Ash.Changeset.get_attribute(changeset, :pay_to)
      end

    Ash.Changeset.force_change_attribute(changeset, :pay_to, pay_to)
  end
end
