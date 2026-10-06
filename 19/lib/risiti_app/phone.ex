defmodule RisitiApp.Phone do
  @moduledoc """
  Kenyan mobile numbers, the way M-Pesa needs them.

  (In the real Risiti this lives in `RisitiApp.Accounts.Profile`, next to the
  signed-in person's own number. Profiles arrive in Part IV.)
  """

  @doc """
  Turns the ways people write a Safaricom or Airtel number into one form:

      iex> RisitiApp.Phone.normalize("0712 345 678")
      {:ok, "+254712345678"}

      iex> RisitiApp.Phone.normalize("254112345678")
      {:ok, "+254112345678"}

      iex> RisitiApp.Phone.normalize("12345")
      :error
  """
  def normalize(raw) when is_binary(raw) do
    digits = String.replace(raw, ~r/[\s\-()]/, "")

    case Regex.run(~r/^(?:\+?254|0)?([17]\d{8})$/, digits) do
      [_, local] -> {:ok, "+254" <> local}
      nil -> :error
    end
  end
end
