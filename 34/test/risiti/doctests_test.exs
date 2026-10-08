defmodule Risiti.DoctestsTest do
  use ExUnit.Case, async: true

  doctest Risiti.Accounts.Phone
  doctest Risiti.Accounts.Permissions
  doctest Risiti.Expenses.PaymentMethod
  doctest Risiti.Expenses
end
