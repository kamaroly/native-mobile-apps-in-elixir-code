defmodule RisitiApp.Transactions.Transaction do
  @moduledoc """
  One expense, whatever form it takes. Its `type` is:

    * `"expense"` — money already spent: Date | Vendor | Description |
      Amount | Category, and the receipt photo when there is one (see
      `RisitiApp.Receipts.Photos`);
    * `"refund"` — an expense the person paid and wants back, to their own
      M-Pesa number unless they change it;
    * `"payment_request"` — money the person asks the team to pay: to a
      supplier (`pay_to: "supplier"`) or to themselves as an advance.

  Refunds and payment requests are *claims*: once approved they wait to be
  paid. Each way of paying (`method`) needs its own details: a phone for
  M-Pesa send money, a till number for Buy Goods, a paybill and account
  number for a paybill.

  Status runs `pending` → `approved` | `rejected`, and for claims
  `approved` → `paid`. Amounts are whole cents so totals never pick up
  floating-point drift.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @categories [
    "Food & Groceries",
    "Meals & Entertainment",
    "Transport",
    "Fuel",
    "Utilities",
    "Airtime & Internet",
    "Rent",
    "Health",
    "Office Supplies",
    "Other"
  ]

  @types ~w(expense refund payment_request)
  @statuses ~w(pending approved rejected paid)
  @methods ~w(cash send_money till paybill card bank other)
  # "manual" when typed in, "photo" when it came with a receipt photo.
  @sources ~w(manual photo)

  @business_number ~r/^\d{5,7}$/

  schema "transactions" do
    field :type, :string, default: "expense"
    field :pay_to, :string
    field :date, :date
    field :vendor, :string
    field :description, :string
    field :amount_cents, :integer
    field :category, :string

    field :method, :string
    field :phone, :string
    field :till_number, :string
    field :paybill_number, :string
    field :account_number, :string

    field :source, :string, default: "manual"
    field :photo_path, :string

    field :status, :string, default: "pending"
    field :decision_note, :string
    field :decided_at, :utc_datetime
    field :paid_at, :utc_datetime

    field :client_id, :string

    timestamps()
  end

  def categories, do: @categories
  def methods, do: @methods
  def statuses, do: @statuses

  @doc "True for refunds and payment requests, which are paid out once approved."
  def claim?(%{type: type}), do: type in ["refund", "payment_request"]

  @doc "Changeset for what the person enters: the figures and, for a claim, how to pay."
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
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
      :account_number,
      :source,
      :photo_path
    ])
    |> trim([:vendor, :description, :phone, :till_number, :paybill_number, :account_number])
    |> validate_required([:type, :date, :vendor, :amount_cents, :category, :source])
    |> validate_inclusion(:type, @types)
    |> validate_number(:amount_cents, greater_than: 0, message: "must be more than zero")
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:source, @sources)
    |> validate_length(:vendor, max: 120)
    |> validate_length(:description, max: 500)
    |> put_pay_to()
    |> validate_type()
    |> validate_method()
    |> unique_constraint(:client_id)
  end

  @doc "Changeset for a decision (and for marking a claim paid)."
  def decision_changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:status, :decision_note, :decided_at, :paid_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:decision_note, max: 300)
  end

  # Nobody for an expense (already paid), the person for a refund, and for
  # a payment request a supplier unless it's an advance to themselves.
  defp put_pay_to(changeset) do
    pay_to =
      case get_field(changeset, :type) do
        "expense" -> nil
        "refund" -> "self"
        "payment_request" -> get_field(changeset, :pay_to) || "supplier"
        _ -> get_field(changeset, :pay_to)
      end

    changeset
    |> put_change(:pay_to, pay_to)
    |> validate_inclusion(:pay_to, ~w(self supplier))
  end

  # A claim says how it's to be paid.
  defp validate_type(changeset) do
    if get_field(changeset, :type) in ["refund", "payment_request"],
      do: validate_required(changeset, [:method], message: "choose how to pay"),
      else: changeset
  end

  defp validate_method(changeset) do
    changeset = validate_inclusion(changeset, :method, @methods)

    case get_field(changeset, :method) do
      "send_money" ->
        changeset
        |> validate_required([:phone], message: "enter the phone number to pay")
        |> normalize_phone()

      "till" ->
        changeset
        |> validate_required([:till_number], message: "enter the till number")
        |> validate_format(:till_number, @business_number, message: "is 5 to 7 digits")

      "paybill" ->
        changeset
        |> validate_required([:paybill_number], message: "enter the paybill number")
        |> validate_format(:paybill_number, @business_number, message: "is 5 to 7 digits")
        |> validate_required([:account_number], message: "enter the account number")
        |> validate_length(:account_number, max: 20)

      _ ->
        changeset
    end
  end

  defp normalize_phone(changeset) do
    case get_field(changeset, :phone) do
      nil ->
        changeset

      raw ->
        case RisitiApp.Phone.normalize(raw) do
          {:ok, phone} -> put_change(changeset, :phone, phone)
          :error -> add_error(changeset, :phone, "is not a valid Kenyan mobile number")
        end
    end
  end

  # "  " becomes nil, so a blank vendor fails validate_required.
  defp trim(changeset, fields) do
    Enum.reduce(fields, changeset, &update_change(&2, &1, fn value -> blank_to_nil(value) end))
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
