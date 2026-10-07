defmodule Risiti.Expenses.PaymentMethod do
  @moduledoc """
  How a transaction was, or is to be, paid. The same for every team.

  Each lists the details it needs (`required_fields`): a phone for M-Pesa
  Send Money, a till number for Buy Goods, a paybill and account number for
  a paybill. `Risiti.Expenses.Transaction.Validations.PaymentDetails`
  enforces them.
  """

  @methods [
    %{code: "cash", name: "Cash", required_fields: []},
    %{code: "send_money", name: "M-Pesa Send Money", required_fields: [:phone]},
    %{code: "till", name: "M-Pesa Buy Goods (Till)", required_fields: [:till_number]},
    %{
      code: "paybill",
      name: "M-Pesa Paybill",
      required_fields: [:paybill_number, :account_number]
    },
    %{code: "card", name: "Card", required_fields: []},
    %{code: "bank", name: "Bank transfer", required_fields: []},
    %{code: "other", name: "Other", required_fields: []}
  ]

  @doc "Every method, in the order to offer them."
  def all, do: @methods

  @doc "The codes: what a transaction's `method` holds."
  def codes, do: Enum.map(@methods, & &1.code)

  @doc """
  The fields `code` needs filled in.

      iex> Risiti.Expenses.PaymentMethod.required_fields("paybill")
      [:paybill_number, :account_number]

      iex> Risiti.Expenses.PaymentMethod.required_fields("cash")
      []
  """
  @spec required_fields(String.t() | nil) :: [atom()]
  def required_fields(code) do
    case Enum.find(@methods, &(&1.code == code)) do
      nil -> []
      method -> method.required_fields
    end
  end
end
