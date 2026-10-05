defmodule RisitiApp.Transactions do
  @moduledoc """
  The expense book, stored in the phone's SQLite database. No network needed.
  """

  import Ecto.Query, only: [from: 2]

  alias RisitiApp.Repo
  alias RisitiApp.Transactions.Transaction

  # Nairobi is UTC+3 all year (no daylight saving), so "today" can be computed
  # without a timezone database, which the phone's runtime doesn't ship.
  @nairobi_offset 3 * 60 * 60

  # The spend card and the filter pills group the categories three ways.
  @groups [
    food: ["Food & Groceries", "Meals & Entertainment"],
    fuel: ["Fuel", "Transport"]
  ]

  defdelegate categories, to: Transaction

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

  @doc "Every transaction, newest first, narrowed to a group unless it's `:all`."
  def list_transactions(filter \\ :all) do
    from(t in Transaction, order_by: [desc: t.date, desc: t.id])
    |> filtered(filter)
    |> Repo.all()
  end

  defp filtered(query, :all), do: query

  defp filtered(query, :other) do
    grouped = Enum.flat_map(@groups, &elem(&1, 1))
    from t in query, where: t.category not in ^grouped
  end

  defp filtered(query, group) do
    categories = Keyword.fetch!(@groups, group)
    from t in query, where: t.category in ^categories
  end

  def get_transaction(id), do: Repo.get(Transaction, id)
  def get_transaction!(id), do: Repo.get!(Transaction, id)

  @doc "For the spend card: what was spent in `month`, in total and per group."
  def summary(month \\ today()) do
    from = Date.beginning_of_month(month)
    to = Date.end_of_month(month)

    per_category =
      Repo.all(
        from t in Transaction,
          where: t.date >= ^from and t.date <= ^to,
          group_by: t.category,
          select: {t.category, sum(t.amount_cents)}
      )

    by_group =
      Enum.reduce(per_category, Map.new(groups(), &{&1, 0}), fn {category, cents}, acc ->
        Map.update!(acc, group(category), &(&1 + cents))
      end)

    %{
      total: by_group |> Map.values() |> Enum.sum(),
      by_group: by_group,
      count: Repo.aggregate(Transaction, :count)
    }
  end

  def create_transaction(attrs) do
    %Transaction{} |> Transaction.changeset(attrs) |> Repo.insert()
  end

  def update_transaction(%Transaction{} = transaction, attrs) do
    transaction |> Transaction.changeset(attrs) |> Repo.update()
  end

  def delete_transaction(%Transaction{} = transaction), do: Repo.delete(transaction)

  @doc "Today's date in Kenya."
  def today do
    DateTime.utc_now() |> DateTime.add(@nairobi_offset, :second) |> DateTime.to_date()
  end

  @doc """
  Reads an amount the way people type it: "1250", "1,250.50", "Ksh 1,250.5".
  Returns `{:ok, cents}` or `:error`. No floats are involved.
  """
  def parse_amount(nil), do: :error

  def parse_amount(text) when is_binary(text) do
    cleaned = text |> String.replace(~r/ksh\.?|kes|[\s,]/i, "")

    case Regex.run(~r/^(\d+)(?:\.(\d{1,2}))?$/, cleaned) do
      [_, shillings] -> {:ok, String.to_integer(shillings) * 100}
      [_, shillings, cents] -> {:ok, String.to_integer(shillings) * 100 + cents_value(cents)}
      nil -> :error
    end
  end

  defp cents_value(<<d>>), do: (d - ?0) * 10
  defp cents_value(two), do: String.to_integer(two)

  @doc "Cents as a plain editable number, e.g. \"1234.50\"; blank for nil."
  def amount_input(nil), do: ""

  def amount_input(cents) do
    "#{div(cents, 100)}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
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
