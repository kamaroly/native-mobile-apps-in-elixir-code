defmodule RisitiApp.Transactions do
  @moduledoc """
  The expense book, stored in the phone's SQLite database. No network needed.
  """

  import Ecto.Query, only: [from: 2]

  alias RisitiApp.Repo
  alias RisitiApp.Receipts.QrParser
  alias RisitiApp.Transactions.{Attachments, Transaction}

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
  def group_label(:claims), do: "Refunds & payments"

  def type_label("expense"), do: "Expense"
  def type_label("refund"), do: "Refund"
  def type_label("payment_request"), do: "Payment request"

  def status_label("pending"), do: "Pending approval"
  def status_label("approved"), do: "Approved"
  def status_label("rejected"), do: "Rejected"
  def status_label("paid"), do: "Paid"

  def method_label("cash"), do: "Cash"
  def method_label("send_money"), do: "Send money"
  def method_label("till"), do: "Till (Buy Goods)"
  def method_label("paybill"), do: "Paybill"
  def method_label("card"), do: "Card"
  def method_label("bank"), do: "Bank transfer"
  def method_label("other"), do: "Other"
  def method_label(nil), do: nil

  @doc """
  Where the money goes, in one line; nil when no way of paying is set.

      iex> RisitiApp.Transactions.pay_details(%RisitiApp.Transactions.Transaction{method: "paybill", paybill_number: "400200", account_number: "12345"})
      "Paybill 400200 · Acc 12345"

      iex> RisitiApp.Transactions.pay_details(%RisitiApp.Transactions.Transaction{method: "send_money", phone: "+254712345678"})
      "M-Pesa 0712 345 678"
  """
  def pay_details(%Transaction{method: "send_money", phone: phone}),
    do: "M-Pesa #{local_phone(phone)}"

  def pay_details(%Transaction{method: "till", till_number: till}), do: "Till #{till}"

  def pay_details(%Transaction{method: "paybill", paybill_number: paybill, account_number: acc}),
    do: "Paybill #{paybill} · Acc #{acc}"

  def pay_details(%Transaction{method: method}), do: method_label(method)

  # "+254712345678" as people write it: "0712 345 678".
  defp local_phone("+254" <> <<a::binary-size(3), b::binary-size(3), c::binary-size(3)>>),
    do: "0#{a} #{b} #{c}"

  defp local_phone(phone), do: phone || ""

  @doc """
  Transactions, newest first. `search` narrows them to those whose vendor,
  description or category contains it; `filter` to a spending group (or
  `:all`); `period` to a date range (see `date_range/2`).
  """
  def list_transactions(search \\ "", filter \\ :all, period \\ :all_dates) do
    from(t in Transaction, order_by: [desc: t.date, desc: t.id], preload: :attachments)
    |> filtered(filter)
    |> dated(date_range(period))
    |> searched(String.trim(search))
    |> Repo.all()
  end

  defp filtered(query, :all), do: query

  defp filtered(query, :claims),
    do: from(t in query, where: t.type in ["refund", "payment_request"])

  defp filtered(query, :other) do
    grouped = Enum.flat_map(@groups, &elem(&1, 1))
    from t in query, where: t.category not in ^grouped
  end

  defp filtered(query, group) do
    categories = Keyword.fetch!(@groups, group)
    from t in query, where: t.category in ^categories
  end

  defp dated(query, {nil, nil}), do: query
  defp dated(query, {from, nil}), do: from(t in query, where: t.date >= ^from)
  defp dated(query, {nil, to}), do: from(t in query, where: t.date <= ^to)
  defp dated(query, {from, to}), do: from(t in query, where: t.date >= ^from and t.date <= ^to)

  defp searched(query, ""), do: query

  # LIKE is case-insensitive for ASCII in SQLite; lower() on both sides
  # makes that explicit. % and _ in what was typed are matched literally.
  defp searched(query, term) do
    pattern = "%" <> escape_like(String.downcase(term)) <> "%"

    from t in query,
      where:
        fragment("lower(?) LIKE ? ESCAPE '\\'", t.vendor, ^pattern) or
          fragment("lower(?) LIKE ? ESCAPE '\\'", t.description, ^pattern) or
          fragment("lower(?) LIKE ? ESCAPE '\\'", t.category, ^pattern) or
          fragment("lower(?) LIKE ? ESCAPE '\\'", t.ocr_text, ^pattern)
  end

  defp escape_like(term), do: String.replace(term, ~r/[\\%_]/, "\\\\\\0")

  # ── Periods ────────────────────────────────────────────────────────────────

  @periods [:all_dates, :today, :last_7_days, :this_month, :last_month, :this_year]

  @doc "The preset periods the date filter offers, in order."
  def periods, do: @periods

  @doc """
  The first and last day of `period`. Either may be nil: no limit that way.

      iex> RisitiApp.Transactions.date_range(:last_month, ~D[2026-03-31])
      {~D[2026-02-01], ~D[2026-02-28]}

      iex> RisitiApp.Transactions.date_range(:last_7_days, ~D[2026-09-29])
      {~D[2026-09-23], ~D[2026-09-29]}

      iex> RisitiApp.Transactions.date_range({:dates, ~D[2026-01-01], nil}, ~D[2026-09-29])
      {~D[2026-01-01], nil}
  """
  def date_range(period, today \\ today())
  def date_range(:all_dates, _today), do: {nil, nil}
  def date_range(:today, today), do: {today, today}
  def date_range(:last_7_days, today), do: {Date.add(today, -6), today}
  def date_range(:this_month, today), do: {Date.beginning_of_month(today), today}

  def date_range(:last_month, today) do
    last_month = today |> Date.beginning_of_month() |> Date.add(-1)
    {Date.beginning_of_month(last_month), last_month}
  end

  def date_range(:this_year, today), do: {Date.new!(today.year, 1, 1), today}
  def date_range({:dates, from, to}, _today), do: {from, to}

  @doc """
  What the date pill says.

      iex> RisitiApp.Transactions.period_label({:dates, ~D[2026-09-01], ~D[2026-09-15]})
      "1 Sep 2026 – 15 Sep 2026"

      iex> RisitiApp.Transactions.period_label({:dates, nil, ~D[2026-09-15]})
      "Up to 15 Sep 2026"
  """
  def period_label(:all_dates), do: "All dates"
  def period_label(:today), do: "Today"
  def period_label(:last_7_days), do: "Last 7 days"
  def period_label(:this_month), do: "This month"
  def period_label(:last_month), do: "Last month"
  def period_label(:this_year), do: "This year"
  def period_label({:dates, from, nil}), do: "From #{format_date(from)}"
  def period_label({:dates, nil, to}), do: "Up to #{format_date(to)}"
  def period_label({:dates, from, to}), do: "#{format_date(from)} – #{format_date(to)}"

  @doc """
  A date the way people write it.

      iex> RisitiApp.Transactions.format_date(~D[2026-09-03])
      "3 Sep 2026"
  """
  def format_date(%Date{} = date), do: "#{date.day} #{Calendar.strftime(date, "%b %Y")}"

  @doc """
  The first day of each of the last `count` months, newest first.

      iex> RisitiApp.Transactions.recent_months(~D[2026-02-14], 3)
      [~D[2026-02-01], ~D[2026-01-01], ~D[2025-12-01]]
  """
  def recent_months(today \\ today(), count) do
    today
    |> Date.beginning_of_month()
    |> Stream.iterate(&Date.beginning_of_month(Date.add(&1, -1)))
    |> Enum.take(count)
  end

  def get_transaction(id), do: Transaction |> Repo.get(id) |> Repo.preload(:attachments)
  def get_transaction!(id), do: Transaction |> Repo.get!(id) |> Repo.preload(:attachments)

  @doc """
  For the spend card: what was spent in `month`, in total and per group.
  Rejected transactions don't count as spend.
  """
  def summary(month \\ today()) do
    from = Date.beginning_of_month(month)
    to = Date.end_of_month(month)

    per_category =
      Repo.all(
        from t in Transaction,
          where: t.date >= ^from and t.date <= ^to and t.status != "rejected",
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

  @doc """
  Saves a new transaction. It gets its `client_id` here, once, and keeps it
  for life: sync is keyed on it.
  """
  def create_transaction(attrs, attachments \\ []) do
    changeset = Transaction.changeset(%Transaction{client_id: Ecto.UUID.generate()}, attrs)

    Repo.transaction(fn ->
      case Repo.insert(changeset) do
        {:ok, transaction} -> with_attachments(transaction, attachments)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # Saves the new attachments against `transaction`, in the same database
  # transaction, and returns it with all of them.
  defp with_attachments(transaction, attachments) do
    Enum.each(attachments, &Repo.insert!(%{&1 | transaction_id: transaction.id}))
    Repo.preload(transaction, :attachments, force: true)
  end

  @doc """
  Updates a transaction. Changing a decided one's figures sends it back for
  approval; a paid one can't be changed.
  """
  def update_transaction(transaction, attrs, attachments \\ [])

  def update_transaction(%Transaction{status: "paid"}, _attrs, _attachments), do: {:error, :paid}

  def update_transaction(%Transaction{} = transaction, attrs, attachments) do
    changeset = transaction |> Transaction.changeset(attrs) |> reopen_if_changed()

    Repo.transaction(fn ->
      case Repo.update(changeset) do
        {:ok, updated} -> with_attachments(updated, attachments)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # A decided transaction whose figures change goes back to the approver:
  # an approval must be for what they actually saw.
  @decided_fields [
    :type,
    :pay_to,
    :date,
    :vendor,
    :description,
    :amount_cents,
    :category,
    :method,
    :phone,
    :till_number,
    :paybill_number,
    :account_number
  ]

  defp reopen_if_changed(%Ecto.Changeset{data: %{status: "pending"}} = changeset),
    do: changeset

  defp reopen_if_changed(changeset) do
    if Enum.any?(@decided_fields, &Map.has_key?(changeset.changes, &1)),
      do:
        Ecto.Changeset.change(changeset, status: "pending", decision_note: nil, decided_at: nil),
      else: changeset
  end

  @doc """
  Asks for an expense back: it becomes a refund, paid as `attrs` say, and
  waits for approval again.
  """
  def request_refund(%Transaction{type: "expense"} = transaction, attrs),
    do: update_transaction(transaction, Map.put(attrs, :type, "refund"))

  def request_refund(%Transaction{}, _attrs), do: {:error, :not_expense}

  @doc "A refund still waiting for a decision can be taken back: it becomes an expense again."
  def cancel_refund(%Transaction{type: "refund", status: "pending"} = transaction) do
    update_transaction(transaction, %{
      type: "expense",
      method: nil,
      phone: nil,
      till_number: nil,
      paybill_number: nil,
      account_number: nil
    })
  end

  def cancel_refund(%Transaction{}), do: {:error, :not_pending}

  @doc """
  Records a decision: `"approved"` or `"rejected"` (with an optional note),
  or `"paid"` once an approved claim has been paid. On the phone these will
  come from the server (Part IV); the function is the same either way.
  """
  def decide(%Transaction{} = transaction, status, note \\ nil) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    transaction
    |> Transaction.decision_changeset(%{
      status: status,
      decision_note: note,
      decided_at: now,
      paid_at: if(status == "paid", do: now)
    })
    |> Repo.update()
  end

  # ── KRA receipts ──────────────────────────────────────────────────────────

  @doc "The saved transaction with this QR code, if any."
  def find_by_qr(qr_content), do: Repo.get_by(Transaction, qr_content: String.trim(qr_content))

  @doc """
  An unsaved expense from a scanned QR code, for the person to confirm. A
  KRA code holds no vendor or total, so those come later: from KRA's page,
  the photo, or the person.
  """
  def new_from_qr(qr_content) do
    parsed = QrParser.parse(qr_content)

    %Transaction{date: today(), category: "Other"}
    |> put_qr(qr_content)
    |> Map.merge(%{date: parsed.date || today(), amount_cents: parsed.amount_cents})
  end

  @doc """
  Puts a QR code on a draft transaction: the code itself and what it
  identifies. Used for a scanned code and for one found in a photo.
  """
  def put_qr(%Transaction{} = transaction, qr_content) do
    parsed = QrParser.parse(qr_content)

    %{
      transaction
      | qr_content: String.trim(qr_content),
        source: parsed.source,
        seller_pin: parsed.seller_pin || transaction.seller_pin,
        branch_id: parsed.branch_id,
        invoice_number: parsed.invoice_number || transaction.invoice_number,
        verify_url: parsed.verify_url
    }
  end

  @doc "True for a receipt whose QR code is a KRA link."
  def kra?(%Transaction{source: source}), do: source in ["etims", "tims", "kra"]

  @doc "True when KRA's page for this receipt can be read: eTIMS and TIMS links only."
  def verifiable?(%Transaction{source: source, verify_url: url}),
    do: source in ["etims", "tims"] and is_binary(url)

  def verified?(%Transaction{verified_at: verified_at}), do: verified_at != nil

  @doc """
  The newest receipt that KRA could verify but hasn't yet, skipping the ids
  in `except` (ones already tried).
  """
  def next_unverified(except \\ []) do
    except = Enum.to_list(except)

    Repo.one(
      from t in Transaction,
        where:
          is_nil(t.verified_at) and t.source in ["etims", "tims"] and not is_nil(t.verify_url) and
            t.id not in ^except,
        order_by: [desc: t.date, desc: t.id],
        limit: 1
    )
  end

  @doc "Records that KRA's page returned this receipt."
  def mark_verified(%Transaction{} = transaction) do
    transaction
    |> Ecto.Changeset.change(verified_at: DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update()
  end

  @doc "Deletes a transaction, its photo and its attachments."
  def delete_transaction(%Transaction{} = transaction) do
    attachments = transaction |> Repo.preload(:attachments) |> Map.fetch!(:attachments)

    with {:ok, deleted} <- Repo.delete(transaction) do
      RisitiApp.Receipts.Photos.delete(deleted.photo_path)
      Attachments.delete(attachments)
      {:ok, deleted}
    end
  end

  @doc "A draft payment request: to a supplier, by M-Pesa send money, until the person says otherwise."
  def new_payment do
    %Transaction{
      type: "payment_request",
      pay_to: "supplier",
      method: "send_money",
      date: today(),
      category: "Other",
      attachments: []
    }
  end

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
