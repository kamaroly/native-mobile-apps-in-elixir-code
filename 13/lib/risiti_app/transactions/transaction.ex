defmodule RisitiApp.Transactions.Transaction do
  @moduledoc """
  One expense: Date | Vendor | Description | Amount | Category.

  Amounts are whole cents so totals never pick up floating-point drift.
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

  @sources ~w(manual)

  schema "transactions" do
    field :type, :string, default: "expense"
    field :date, :date
    field :vendor, :string
    field :description, :string
    field :amount_cents, :integer
    field :category, :string
    field :source, :string, default: "manual"

    timestamps()
  end

  def categories, do: @categories

  @doc "Changeset for what the person enters."
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:date, :vendor, :description, :amount_cents, :category, :source])
    |> trim([:vendor, :description])
    |> validate_required([:date, :vendor, :amount_cents, :category, :source])
    |> validate_number(:amount_cents, greater_than: 0, message: "must be more than zero")
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:source, @sources)
    |> validate_length(:vendor, max: 120)
    |> validate_length(:description, max: 500)
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
