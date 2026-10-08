defmodule RisitiApp.Transactions.Report do
  @moduledoc """
  The transactions on screen as a PDF: the dates and filters they were
  picked by, a table oldest first, and the total. Like the spend card, the
  total leaves out rejected transactions.

  The file goes in `exports/` in the app's data directory (see
  `RisitiApp.DataDir`), replacing the last one, and the phone's PDF viewer
  opens it from there — to read, print or share.
  """

  alias RisitiApp.{DataDir, Pdf, Transactions}

  @margin 40
  @row 18
  # The description, when there is one, goes on a second line.
  @row_with_note 28
  @header_row 20

  # {title, width, align}: 515 points between the margins.
  @columns [
    {"Date", 62, :left},
    {"Vendor / payee", 120, :left},
    {"Category", 104, :left},
    {"Type", 78, :left},
    {"Status", 64, :left},
    {"Amount", 87, :right}
  ]

  @doc "Writes the PDF and returns its path."
  def write(transactions, scope) do
    dir = DataDir.path("exports")
    Enum.each(File.ls!(dir), &File.rm(Path.join(dir, &1)))

    path = Path.join(dir, file_name(scope.period))

    with :ok <- File.write(path, render(transactions, scope)), do: {:ok, path}
  end

  @doc "The PDF itself."
  def render(transactions, scope, today \\ Transactions.today()) do
    rows = transactions |> Enum.sort_by(& &1.id) |> Enum.sort_by(& &1.date, Date)
    {_width, height} = Pdf.page_size()

    first_top = height - @margin
    {heading, top} = heading(rows, scope, today, first_top)

    pages =
      rows
      |> paginate(top, height - @margin)
      |> case do
        [] -> [[]]
        pages -> pages
      end

    count = length(pages)

    pages
    |> Enum.with_index(1)
    |> Enum.map(fn {page_rows, n} ->
      page_top = if n == 1, do: top, else: height - @margin
      {table, bottom} = table(page_rows, page_top)

      empty =
        if rows == [],
          do: [{:text, @margin, bottom - 18, 11, :regular, "Nothing to show.", 0.4}],
          else: []

      total = if n == count and rows != [], do: total(rows, bottom), else: []

      if(n == 1, do: heading, else: []) ++ table ++ empty ++ total ++ footer(n, count, today)
    end)
    |> Pdf.render(title(scope.period))
  end

  # Splits the rows into pages: the first starts under the heading, the
  # rest at the top; the last leaves room for the total.
  defp paginate(rows, first_top, top) do
    bottom = @margin + 30

    {pages, current, _y} =
      Enum.reduce(rows, {[], [], first_top - @header_row}, fn row, {pages, current, y} ->
        h = row_height(row)

        if y - h < bottom and current != [],
          do: {[Enum.reverse(current) | pages], [row], top - @header_row - h},
          else: {pages, [row | current], y - h}
      end)

    pages = if current == [], do: pages, else: [Enum.reverse(current) | pages]
    Enum.reverse(pages)
  end

  defp heading(rows, scope, today, top) do
    lines =
      [
        "Dates: " <> dates_line(scope.period, today),
        scope.filter && "Showing: " <> scope.filter,
        present(scope.search) && "Search: “#{String.trim(scope.search)}”",
        "#{count_label(rows)} · made #{Transactions.format_date(today)}"
      ]
      |> Enum.filter(& &1)

    title = [{:text, @margin, top - 22, 20, :bold, "Transactions"}]

    {ops, y} =
      Enum.reduce(lines, {title, top - 44}, fn line, {ops, y} ->
        {[{:text, @margin, y, 10, :regular, line, 0.35} | ops], y - 14}
      end)

    {Enum.reverse(ops), y - 10}
  end

  defp count_label([_]), do: "1 transaction"
  defp count_label(rows), do: "#{length(rows)} transactions"

  # A preset also says which dates it meant on the day it was made.
  defp dates_line({:dates, _, _} = period, _today), do: Transactions.period_label(period)
  defp dates_line(:all_dates, _today), do: "All dates"

  defp dates_line(period, today) do
    {from, to} = Transactions.date_range(period, today)
    label = Transactions.period_label({:dates, from, to})
    "#{Transactions.period_label(period)} (#{label})"
  end

  defp table(rows, top) do
    header_y = top - 14

    header =
      [{:box, @margin, top - @header_row, 515, @header_row, 0.93}] ++
        cells(Enum.map(@columns, &elem(&1, 0)), header_y, 9, :bold, 0.25)

    {body, bottom} =
      Enum.reduce(rows, {[], top - @header_row}, fn row, {ops, y} ->
        h = row_height(row)
        text_y = y - 12
        muted = if row.status == "rejected", do: 0.55, else: 0

        cells =
          cells(
            [
              Transactions.format_date(row.date),
              row.vendor || "",
              row.category || "",
              Transactions.type_label(row.type),
              short_status(row.status),
              Transactions.format_amount(row.amount_cents)
            ],
            text_y,
            9,
            :regular,
            muted
          )

        note =
          if present(row.description),
            do: [
              {:text, @margin + 62 + 4, text_y - 10, 7.5, :regular,
               Pdf.fit(String.trim(row.description), 360, 7.5), 0.45}
            ],
            else: []

        line = [{:line, @margin, y - h, @margin + 515, y - h, 0.85}]
        {ops ++ cells ++ note ++ line, y - h}
      end)

    {header ++ body, bottom}
  end

  defp cells(values, y, size, font, gray) do
    @columns
    |> Enum.zip(values)
    |> Enum.map_reduce(@margin, fn {{_title, width, align}, value}, x ->
      text = Pdf.fit(value, width - 8, size, font)

      x_text =
        if align == :right,
          do: x + width - 4 - Pdf.text_width(text, size, font),
          else: x + 4

      {{:text, x_text, y, size, font, text, gray}, x + width}
    end)
    |> elem(0)
  end

  defp total(rows, bottom) do
    counted = Enum.reject(rows, &(&1.status == "rejected"))
    cents = counted |> Enum.map(&(&1.amount_cents || 0)) |> Enum.sum()
    amount = Transactions.format_amount(cents)
    right = @margin + 515 - 4
    y = bottom - 20

    label =
      if length(counted) == length(rows),
        do: "Total",
        else: "Total, leaving out rejected"

    [
      {:text, @margin + 4, y, 10, :bold, label},
      {:text, right - Pdf.text_width(amount, 10, :bold), y, 10, :bold, amount}
    ]
  end

  defp footer(n, count, today) do
    text = "Risiti · #{Transactions.format_date(today)} · page #{n} of #{count}"
    [{:text, @margin, @margin - 16, 8, :regular, text, 0.5}]
  end

  defp row_height(row), do: if(present(row.description), do: @row_with_note, else: @row)

  defp short_status("pending"), do: "Pending"
  defp short_status(status), do: Transactions.status_label(status)

  defp present(text), do: is_binary(text) and String.trim(text) != ""

  defp title(period), do: "Transactions – " <> Transactions.period_label(period)

  defp file_name(period) do
    slug =
      period
      |> Transactions.period_label()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    "risiti-transactions-#{slug}.pdf"
  end
end
