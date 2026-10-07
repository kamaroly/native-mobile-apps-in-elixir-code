defmodule Risiti.Expenses.Transaction.Changes.ReopenIfFiguresChanged do
  @moduledoc """
  A decided transaction whose figures (type, date, vendor, amount, category,
  how to pay…) change goes back to pending: an approval must be for what
  the approver actually saw.
  """

  use Ash.Resource.Change

  alias Risiti.Expenses.Transaction

  @impl true
  def change(%{data: %{status: :pending}} = changeset, _opts, _context), do: changeset

  def change(changeset, _opts, _context) do
    # Compared by value: a resend carries every field, changed or not.
    changed? =
      Enum.any?(Transaction.figures(), fn field ->
        Ash.Changeset.get_attribute(changeset, field) != Map.get(changeset.data, field)
      end)

    if changed? do
      Ash.Changeset.force_change_attributes(changeset, %{
        status: :pending,
        decision_note: nil,
        decided_at: nil,
        decided_by_id: nil
      })
    else
      changeset
    end
  end
end
