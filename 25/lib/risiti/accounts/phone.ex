defmodule Risiti.Accounts.Phone do
  @moduledoc "Kenyan mobile numbers, with the same rules as the phone app."

  @doc """
  Normalises a Kenyan mobile number to `+254XXXXXXXXX`.

      iex> Risiti.Accounts.Phone.normalize("0712 345 678")
      {:ok, "+254712345678"}

      iex> Risiti.Accounts.Phone.normalize("254110000000")
      {:ok, "+254110000000"}

      iex> Risiti.Accounts.Phone.normalize("12345")
      :error
  """
  @spec normalize(String.t()) :: {:ok, String.t()} | :error
  def normalize(raw) when is_binary(raw) do
    digits = String.replace(raw, ~r/[\s\-()]/, "")

    case Regex.run(~r/^(?:\+?254|0)?([17]\d{8})$/, digits) do
      [_, local] -> {:ok, "+254" <> local}
      nil -> :error
    end
  end

  def normalize(_raw), do: :error
end
