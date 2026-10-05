defmodule RisitiApp.TransactionsTest do
  use ExUnit.Case, async: false

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Transactions

  setup :checkout_repo

  test "create_transaction/1 saves an expense and trims the vendor" do
    assert {:ok, saved} =
             Transactions.create_transaction(%{
               date: ~D[2026-10-02],
               vendor: "  Java House ",
               amount_cents: 87_000,
               category: "Meals & Entertainment"
             })

    assert saved.vendor == "Java House"
    assert saved.source == "manual"
  end

  test "create_transaction/1 refuses a blank vendor, a zero amount and an unknown category" do
    assert {:error, changeset} =
             Transactions.create_transaction(%{
               date: ~D[2026-10-02],
               vendor: "  ",
               amount_cents: 0,
               category: "Snacks"
             })

    assert %{
             vendor: ["can't be blank"],
             amount_cents: ["must be more than zero"],
             category: ["is invalid"]
           } = errors_on(changeset)
  end

  test "summary/1 adds up one month, per group" do
    insert_transaction(date: ~D[2026-10-03], category: "Food & Groceries", amount_cents: 345_050)
    insert_transaction(date: ~D[2026-10-02], category: "Fuel", amount_cents: 450_000)

    insert_transaction(
      date: ~D[2026-10-01],
      category: "Airtime & Internet",
      amount_cents: 100_000
    )

    insert_transaction(date: ~D[2026-09-30], category: "Transport", amount_cents: 64_000)

    summary = Transactions.summary(~D[2026-10-15])

    assert summary.total == 895_050
    assert summary.by_group == %{food: 345_050, fuel: 450_000, other: 100_000}
    assert summary.count == 4
  end

  test "list_transactions/1 is newest first" do
    insert_transaction(vendor: "Older", date: ~D[2026-09-01])
    insert_transaction(vendor: "Newer", date: ~D[2026-10-01])

    assert Enum.map(Transactions.list_transactions(), & &1.vendor) == ["Newer", "Older"]
  end

  test "group/1 sorts categories into food, fuel and other" do
    assert Transactions.group("Meals & Entertainment") == :food
    assert Transactions.group("Transport") == :fuel
    assert Transactions.group("Rent") == :other
  end

  test "format_amount/1 and format_short/1 show shillings" do
    assert Transactions.format_amount(345_050) == "Ksh 3,450.50"
    assert Transactions.format_amount(5) == "Ksh 0.05"
    assert Transactions.format_short(450_000) == "Ksh 4,500"
    assert Transactions.format_short(345_050) == "Ksh 3,450.50"
  end

  test "parse_amount/1 reads amounts the way people type them" do
    assert Transactions.parse_amount("1250") == {:ok, 125_000}
    assert Transactions.parse_amount("1,250.5") == {:ok, 125_050}
    assert Transactions.parse_amount("Ksh 870.05") == {:ok, 87_005}
    assert Transactions.parse_amount("12.345") == :error
    assert Transactions.parse_amount("abc") == :error
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
