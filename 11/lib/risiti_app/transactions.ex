defmodule RisitiApp.Transactions do
  @moduledoc """
  The expense book. For now the receipts are hard-coded; Chapter 12 moves
  them into SQLite without changing what the screens call.
  """

  # Nairobi is UTC+3 all year (no daylight saving), so "today" can be computed
  # without a timezone database, which the phone's runtime doesn't ship.
  @nairobi_offset 3 * 60 * 60

  # The spend card and the filter pills group the categories three ways.
  @groups [
    food: ["Food & Groceries", "Meals & Entertainment"],
    fuel: ["Fuel", "Transport"]
  ]

  @sample [
    %{
      id: 1,
      date: ~D[2026-10-03],
      vendor: "Naivas Supermarket",
      category: "Food & Groceries",
      amount_cents: 345_050
    },
    %{
      id: 2,
      date: ~D[2026-10-02],
      vendor: "TotalEnergies Westlands",
      category: "Fuel",
      amount_cents: 450_000
    },
    %{
      id: 3,
      date: ~D[2026-10-02],
      vendor: "Java House",
      category: "Meals & Entertainment",
      amount_cents: 87_000
    },
    %{
      id: 4,
      date: ~D[2026-10-01],
      vendor: "Safaricom",
      category: "Airtime & Internet",
      amount_cents: 100_000
    },
    %{
      id: 5,
      date: ~D[2026-09-30],
      vendor: "Little Cab",
      category: "Transport",
      amount_cents: 64_000
    },
    %{
      id: 6,
      date: ~D[2026-09-29],
      vendor: "Text Book Centre",
      category: "Office Supplies",
      amount_cents: 75_000
    }
  ]

  def groups, do: [:food, :fuel, :other]

  @doc "The spending group a category belongs to: :food, :fuel or :other."
  def group(category) do
    Enum.find_value(@groups, :other, fn {group, categories} ->
      if category in categories, do: group
    end)
  end

  def group_label(:food), do: "Food"
  def group_label(:fuel), do: "Fuel"
  def group_label(:other), do: "Other"

  @doc "Every receipt, newest first, narrowed to a group unless it's `:all`."
  def list_transactions(filter \\ :all)
  def list_transactions(:all), do: Enum.sort_by(@sample, & &1.date, {:desc, Date})

  def list_transactions(group),
    do: Enum.filter(list_transactions(:all), &(group(&1.category) == group))

  def get_transaction(id), do: Enum.find(@sample, &(&1.id == id))

  @doc "Today's date in Kenya."
  def today do
    DateTime.utc_now() |> DateTime.add(@nairobi_offset, :second) |> DateTime.to_date()
  end

  @doc "For the spend card: what was spent in `month`, in total and per group."
  def summary(month \\ today()) do
    in_month =
      Enum.filter(@sample, &(&1.date.year == month.year and &1.date.month == month.month))

    by_group =
      Map.new(groups(), fn group ->
        {group, for(t <- in_month, group(t.category) == group, do: t.amount_cents) |> Enum.sum()}
      end)

    %{total: by_group |> Map.values() |> Enum.sum(), by_group: by_group, count: length(@sample)}
  end

  @doc "Cents as shillings: 345_050 -> \"Ksh 3,450.50\"."
  def format_amount(cents) do
    shillings =
      div(cents, 100)
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/.{3}(?=.)/, "\\0,")
      |> String.reverse()

    "Ksh #{shillings}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  @doc "Like `format_amount/1`, without the cents when there are none: \"Ksh 4,500\"."
  def format_short(cents) do
    amount = format_amount(cents)
    if String.ends_with?(amount, ".00"), do: String.slice(amount, 0..-4//1), else: amount
  end
end
