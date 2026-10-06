defmodule RisitiApp.Receipts.KraReceipt do
  @moduledoc """
  Reads a receipt's details off KRA's verification page — the page a
  receipt's QR code links to.

  The QR code itself only identifies the receipt (see
  `RisitiApp.Receipts.QrParser`); the vendor, date, total and items are on
  KRA's side. Two page layouts are understood:

    * **eTIMS** (`etims.kra.go.ke/...indexEtimsReceiptData`): the seller's
      name heads the page, then the items, `TOTAL`, and `Date :` under
      "SCU INFORMATION".
    * **TIMS / ETR** (`itax.kra.go.ke/...invoiceChk.htm`): iTax's invoice
      checker, a table of `<b>Label</b>` cells each followed by its value.

  Parsing is separate from fetching so it can be tested against saved pages.
  """

  alias RisitiApp.Transactions

  @type details :: %{
          vendor: String.t() | nil,
          date: Date.t() | nil,
          amount_cents: non_neg_integer() | nil,
          description: String.t() | nil,
          invoice_number: String.t() | nil
        }

  @timeout 15_000

  @doc """
  Fetches `url` (a KRA link from `QrParser`) and parses it. Blocks for up to
  #{div(@timeout, 1000)} seconds, so call it off the screen process.
  """
  @spec fetch(String.t()) :: {:ok, details()} | {:error, term()}
  def fetch(url) do
    case RisitiApp.Http.get(url, timeout: @timeout) do
      {:ok, 200, html} when is_binary(html) -> parse(html)
      {:ok, status, _body} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Parses a KRA verification page. `{:error, :unrecognised}` when it holds no receipt."
  @spec parse(String.t()) :: {:ok, details()} | {:error, :unrecognised}
  def parse(html) when is_binary(html) do
    details =
      cond do
        html =~ "Supplier Name" -> parse_tims(html)
        html =~ "topinfo" -> parse_etims(html)
        true -> nil
      end

    case details do
      %{vendor: vendor, amount_cents: cents} = found
      when is_binary(vendor) or is_integer(cents) ->
        {:ok, found}

      _ ->
        {:error, :unrecognised}
    end
  end

  # ── eTIMS ──────────────────────────────────────────────────────────────────

  defp parse_etims(html) do
    top = section(html, ~r/<div class="topinfo[^"]*">(.*?)<hr/s)

    items =
      ~r/<div class="tit">(.*?)<\/div>/s
      |> Regex.scan(html, capture: :all_but_first)
      |> Enum.map(fn [item] -> item |> text() |> item_name() end)
      |> Enum.reject(&(&1 == ""))

    %{
      vendor: top |> first_div() |> tidy_name(),
      date: html |> etims_value("Date") |> parse_date(),
      amount_cents: html |> etims_value("TOTAL") |> parse_amount(),
      description: describe(items),
      invoice_number: capture(~r/Invoice Number\s*:\s*([^<]+)</, top)
    }
  end

  # `<span class="tit lt">LABEL</span> : <span class="value ...">VALUE</span>`
  # — matched on the exact label so "TOTAL" doesn't hit "TOTAL TAX".
  defp etims_value(html, label) do
    regex =
      ~r/<span class="tit[^"]*"[^>]*>\s*#{Regex.escape(label)}\s*(?::|&nbsp;)*\s*<\/span>\s*:?\s*<span class="value[^"]*">([^<]*)</

    capture(regex, html)
  end

  defp first_div(nil), do: nil
  defp first_div(top), do: capture(~r/<div>([^<]+)<\/div>/, top)

  # "KE2OUL0000001 : UNLEADED" is an item code and its name.
  defp item_name(item) do
    case String.split(item, " : ", parts: 2) do
      [_code, name] -> tidy_name(name)
      [name] -> tidy_name(name)
    end
  end

  # ── TIMS (iTax invoice checker) ───────────────────────────────────────────

  defp parse_tims(html) do
    %{
      vendor: html |> tims_value("Supplier Name") |> tidy_name(),
      date: html |> tims_value("Invoice Date") |> parse_date(),
      amount_cents: html |> tims_value("Total Invoice Amount") |> parse_amount(),
      description: nil,
      invoice_number: tims_value(html, "Control Unit Invoice Number")
    }
  end

  # The value is the first non-empty <td> after the label's cell; the page
  # leaves an empty cell from an unrendered JSP branch in front of some.
  defp tims_value(html, label) do
    case Regex.run(~r/<b>\s*#{Regex.escape(label)}\s*<\/b>\s*<\/td>(.*)/s, html) do
      [_, rest] ->
        ~r/<td[^>]*>([^<]*)<\/td>/
        |> Regex.scan(rest, capture: :all_but_first)
        |> Enum.map(fn [value] -> text(value) end)
        |> Enum.find(&(&1 != ""))

      nil ->
        nil
    end
  end

  # ── Values ─────────────────────────────────────────────────────────────────

  defp parse_date(nil), do: nil

  defp parse_date(text) do
    with [_, d, m, y] <- Regex.run(~r/(\d{1,2})\/(\d{1,2})\/(\d{4})/, text),
         {:ok, date} <- Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d)) do
      date
    else
      _ -> nil
    end
  end

  defp parse_amount(nil), do: nil

  defp parse_amount(text) do
    case Transactions.parse_amount(text) do
      {:ok, cents} when cents > 0 -> cents
      _ -> nil
    end
  end

  defp describe([]), do: nil
  defp describe(items), do: items |> Enum.uniq() |> Enum.join(", ") |> String.slice(0, 500)

  @doc """
  Title-cases a name KRA returns in capitals; leaves mixed case alone.

      iex> RisitiApp.Receipts.KraReceipt.tidy_name("QUICK MART LIMITED")
      "Quick Mart Limited"

      iex> RisitiApp.Receipts.KraReceipt.tidy_name("Stabex International Limited")
      "Stabex International Limited"
  """
  @spec tidy_name(String.t() | nil) :: String.t() | nil
  def tidy_name(nil), do: nil

  def tidy_name(name) do
    name = text(name)

    cond do
      name == "" ->
        nil

      name == String.upcase(name) ->
        name |> String.split() |> Enum.map_join(" ", &String.capitalize/1)

      true ->
        name
    end
  end

  defp section(html, regex) do
    case Regex.run(regex, html) do
      [_, inner] -> inner
      nil -> nil
    end
  end

  defp capture(_regex, nil), do: nil

  defp capture(regex, html) do
    case Regex.run(regex, html) do
      [_, value] -> text(value)
      nil -> nil
    end
  end

  defp text(html) do
    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
