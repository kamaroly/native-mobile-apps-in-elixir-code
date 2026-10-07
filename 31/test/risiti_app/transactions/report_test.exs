defmodule RisitiApp.Transactions.ReportTest do
  use ExUnit.Case, async: false

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Transactions
  alias RisitiApp.Transactions.Report

  setup :checkout_repo

  @today ~D[2026-10-06]
  @scope %{period: :last_month, filter: nil, search: ""}

  defp expense(attrs) do
    insert_transaction(Map.merge(%{date: ~D[2026-09-12], amount_cents: 100_000}, Map.new(attrs)))
  end

  test "heads the table with the dates and filters it was made from" do
    pdf =
      Report.render(
        [expense(vendor: "Java House")],
        %{@scope | filter: "Food", search: "java"},
        @today
      )

    assert "%PDF-1.4" <> _ = pdf
    assert pdf =~ "(Dates: Last month \\(1 Sep 2026 "
    assert pdf =~ "(Showing: Food)"
    assert pdf =~ "1 transaction"
    assert pdf =~ "(Java House)"
  end

  test "the total leaves out rejected transactions, and says so" do
    {:ok, rejected} =
      Transactions.decide(expense(vendor: "Personal", amount_cents: 50_000), "rejected")

    pdf =
      Report.render([expense(vendor: "Naivas", amount_cents: 245_000), rejected], @scope, @today)

    assert pdf =~ "(Total, leaving out rejected)"
    assert pdf =~ "(Ksh 2,450.00)"
  end

  test "a long list runs onto more pages, each numbered" do
    rows = for i <- 1..60, do: expense(vendor: "Shop #{i}")
    pdf = Report.render(rows, @scope, @today)

    [_, count] = Regex.run(~r/\/Count (\d+)/, pdf)
    pages = String.to_integer(count)
    assert pages > 1
    assert pdf =~ "page #{pages} of #{pages}"
  end

  test "an empty list still makes a page that says so" do
    pdf = Report.render([], @scope, @today)
    assert pdf =~ "/Count 1"
    assert pdf =~ "(Nothing to show.)"
  end

  test "write/2 keeps one file in exports, named for the period" do
    {:ok, first} = Report.write([expense(vendor: "Naivas")], @scope)
    {:ok, second} = Report.write([expense(vendor: "Naivas")], %{@scope | period: :this_year})

    assert Path.basename(second) == "risiti-transactions-this-year.pdf"
    refute File.exists?(first)
    assert File.ls!(Path.dirname(second)) == [Path.basename(second)]
  end
end
