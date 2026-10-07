defmodule Risiti.Expenses.Export do
  @moduledoc """
  Approved and paid transactions as a file an accountant imports.

  Every transaction is one balanced entry:

    * debit its category's expense account with the amount before VAT, and
      the VAT account with the VAT, if any;
    * credit the account that paid (by payment method), or, for a refund or
      payment request that's approved but not paid yet, claims payable:
      the team owes the money.

  Two formats:

    * `:transactions`: every detail, one row each (CSV), for anything;
    * `:quickbooks`: QuickBooks Online journal entries (CSV), for Settings →
      Import data → Journal entries.

  Account names must match the team's chart of accounts in QuickBooks. The
  book's server uses these defaults for every team; the real Risiti lets
  each team set its own.
  """

  alias Risiti.Expenses.Transaction

  @accounts %{
    cash: "Petty Cash",
    mpesa: "M-Pesa",
    card: "Credit Card",
    bank: "Bank",
    other: "Suspense",
    vat: "VAT Input",
    payable: "Staff Claims Payable"
  }

  @formats [
    transactions: "Transactions (CSV)",
    quickbooks: "QuickBooks Online journal entries (CSV)"
  ]

  @doc "The formats, as `{id, name}`, in the order to offer them."
  def formats, do: @formats

  @doc "The CSV for `transactions` (with `:user` loaded) in `format`."
  @spec build(:transactions | :quickbooks, [Transaction.t()]) :: binary()
  def build(format, transactions) do
    {headers, rows} = rows(format, Enum.map(transactions, &entry/1))

    [headers | rows]
    |> Enum.map(fn row -> Enum.map(row, &(&1 || "")) end)
    |> NimbleCSV.RFC4180.dump_to_iodata()
    |> IO.iodata_to_binary()
  end

  # ── One transaction, as an entry ───────────────────────────────────────────

  defp entry(%Transaction{} = t) do
    tax = t.tax_cents || 0
    unpaid_claim? = t.type in ["refund", "payment_request"] and t.status != :paid

    %{
      t: t,
      ref: reference(t),
      label: [t.vendor, t.description] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" — "),
      credit_account: if(unpaid_claim?, do: @accounts.payable, else: paying_account(t.method)),
      gross: t.amount_cents,
      tax: tax,
      net: t.amount_cents - tax
    }
  end

  # Short and unique: the random end of the transaction's id.
  defp reference(t),
    do: "RIS-" <> (t.id |> String.replace("-", "") |> String.slice(-10, 10) |> String.upcase())

  defp paying_account("cash"), do: @accounts.cash

  defp paying_account(method) when method in ["send_money", "till", "paybill"],
    do: @accounts.mpesa

  defp paying_account("card"), do: @accounts.card
  defp paying_account("bank"), do: @accounts.bank
  defp paying_account(_other), do: @accounts.other

  # ── Formats ───────────────────────────────────────────────────────────────

  defp rows(:transactions, entries) do
    {~w(Date Reference Type Status Vendor Description Category Amount VAT Net) ++
       ["Paid with", "Credit account", "Sent by", "Decided at", "Paid at", "Seller KRA PIN"],
     Enum.map(entries, fn %{t: t} = e ->
       [
         Date.to_iso8601(t.date),
         e.ref,
         t.type,
         to_string(t.status),
         t.vendor,
         t.description,
         t.category,
         money(e.gross),
         money(e.tax),
         money(e.net),
         t.method,
         e.credit_account,
         t.user && t.user.name,
         t.decided_at && DateTime.to_iso8601(t.decided_at),
         t.paid_at && DateTime.to_iso8601(t.paid_at),
         t.seller_pin
       ]
     end)}
  end

  defp rows(:quickbooks, entries) do
    {["Journal No.", "Journal Date", "Account Name", "Debits", "Credits", "Description", "Name"],
     Enum.flat_map(entries, fn %{t: t} = e ->
       line = fn account, debit, credit ->
         [e.ref, Calendar.strftime(t.date, "%d/%m/%Y"), account, debit, credit, e.label, t.vendor]
       end

       vat = if e.tax > 0, do: [line.(@accounts.vat, money(e.tax), nil)], else: []

       [line.(t.category, money(e.net), nil)] ++
         vat ++ [line.(e.credit_account, nil, money(e.gross))]
     end)}
  end

  # Plain decimals, no thousands separator: what importers expect.
  defp money(cents),
    do:
      "#{div(cents, 100)}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
end
