defmodule Risiti.Expenses.TransactionType do
  @moduledoc """
  What a transaction is. The same three for every team:

    * **expense**: money already spent, recorded for the books;
    * **refund**: money the person spent and wants back;
    * **payment_request**: money the person asks the team to pay out, to a
      supplier or to themselves (an advance).

  Refunds and payment requests are *claims*: once approved, they wait to be
  paid (`payable?`).
  """

  @types [
    %{
      code: "expense",
      name: "Expense",
      description: "Money already spent, recorded for the books",
      payable?: false
    },
    %{
      code: "refund",
      name: "Refund",
      description: "Money you spent and want back",
      payable?: true
    },
    %{
      code: "payment_request",
      name: "Payment request",
      description: "Ask the team to pay a supplier, or to advance you money",
      payable?: true
    }
  ]

  @doc "The three types, in the order to offer them."
  def all, do: @types

  @doc "The codes: what a transaction's `type` holds."
  def codes, do: Enum.map(@types, & &1.code)
end
