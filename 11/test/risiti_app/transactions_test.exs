defmodule RisitiApp.TransactionsTest do
  use ExUnit.Case, async: true

  alias RisitiApp.Transactions

  test "group/1 sorts categories into food, fuel and other" do
    assert Transactions.group("Meals & Entertainment") == :food
    assert Transactions.group("Transport") == :fuel
    assert Transactions.group("Rent") == :other
  end

  test "summary/1 adds up one month, per group" do
    summary = Transactions.summary(~D[2026-10-01])

    assert summary.total == 982_050
    assert summary.by_group == %{food: 432_050, fuel: 450_000, other: 100_000}
  end

  test "format_amount/1 and format_short/1 show shillings" do
    assert Transactions.format_amount(345_050) == "Ksh 3,450.50"
    assert Transactions.format_amount(5) == "Ksh 0.05"
    assert Transactions.format_short(450_000) == "Ksh 4,500"
    assert Transactions.format_short(345_050) == "Ksh 3,450.50"
  end
end
