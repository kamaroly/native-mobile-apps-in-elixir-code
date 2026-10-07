defmodule Risiti.Expenses do
  @moduledoc """
  A team's spending: its transactions and the categories they're filed
  under. Everything here lives in the team's own schema.
  """

  use Ash.Domain, otp_app: :risiti, extensions: [AshPaperTrail.Domain]

  # Each resource's history (its `Version` resource) belongs to this domain too.
  paper_trail do
    include_versions?(true)
  end

  resources do
    resource Risiti.Expenses.Category

    resource Risiti.Expenses.Transaction do
      define :sync_transaction, action: :sync, args: [:attrs]
      define :own_transaction, action: :own, args: [:client_id], not_found_error?: false
    end

    resource Risiti.Expenses.Attachment
  end

  # ── Shared with the phone ─────────────────────────────────────────────────
  # The receipt parsers (OcrParser, QrParser) are copies of the phone's, and
  # call these as the phone calls RisitiApp.Transactions.

  @nairobi_offset 3 * 60 * 60

  @doc "Today's date in Kenya."
  def today do
    DateTime.utc_now() |> DateTime.add(@nairobi_offset, :second) |> DateTime.to_date()
  end

  @doc """
  Reads an amount the way people type it: "1250", "1,250.50", "Ksh 1,250.5".
  Returns `{:ok, cents}` or `:error`. No floats are involved.

      iex> Risiti.Expenses.parse_amount("Ksh 1,250.5")
      {:ok, 125050}
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

  @doc """
  Cents as shillings.

      iex> Risiti.Expenses.format_amount(345_050)
      "Ksh 3,450.50"
  """
  def format_amount(cents) do
    shillings =
      div(cents, 100)
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/.{3}(?=.)/, "\\0,")
      |> String.reverse()

    "Ksh #{shillings}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end
end
