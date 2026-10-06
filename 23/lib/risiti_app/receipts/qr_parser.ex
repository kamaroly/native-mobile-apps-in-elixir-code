defmodule RisitiApp.Receipts.QrParser do
  @moduledoc """
  Reads what it can out of a receipt's QR code, with no network access.

  An eTIMS QR code is a link to KRA's verification page:

      https://etims.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=P051234567X00ABCDEF0123456789

  `Data` is the seller's KRA PIN (11 characters), the branch id (2 digits) and
  the receipt signature, back to back. That is all the code holds — the vendor
  name, date and total live on KRA's side — so those fields come back `nil` and
  the user fills them in from the paper receipt.

  Older TIMS (ETR) receipts link to the iTax invoice checker with an
  `invoiceNo`. Anything else is kept as raw text; if it happens to spell out a
  date, a total or a PIN (some printers encode a text summary) those are
  picked up.
  """

  @type result :: %{
          source: String.t(),
          seller_pin: String.t() | nil,
          branch_id: String.t() | nil,
          invoice_number: String.t() | nil,
          verify_url: String.t() | nil,
          date: Date.t() | nil,
          amount_cents: non_neg_integer() | nil,
          vendor: String.t() | nil
        }

  @kra_pin ~r/\b([AP]\d{9}[A-Z])\b/

  @spec parse(String.t()) :: result()
  def parse(content) when is_binary(content) do
    content = String.trim(content)

    case kra_link(content) do
      {:ok, uri, query} -> parse_link(content, uri, query)
      :error -> parse_text(content)
    end
  end

  defp parse_link(content, uri, query) do
    cond do
      String.contains?(uri.path || "", "indexEtimsReceiptData") and is_binary(query["Data"]) ->
        parse_etims(content, query["Data"])

      is_binary(query["invoiceNo"]) ->
        %{blank("tims") | invoice_number: query["invoiceNo"], verify_url: content}

      true ->
        %{blank("kra") | verify_url: content}
    end
  end

  defp parse_etims(content, data) do
    data = String.upcase(data)

    case Regex.run(~r/^([AP]\d{9}[A-Z])(\d{2})([A-Z0-9]+)$/, data) do
      [_, pin, branch, signature] ->
        %{
          blank("etims")
          | seller_pin: pin,
            branch_id: branch,
            invoice_number: signature,
            verify_url: content
        }

      nil ->
        %{blank("etims") | invoice_number: data, verify_url: content}
    end
  end

  defp parse_text(content) do
    %{
      blank("other")
      | seller_pin: capture(@kra_pin, content),
        date: find_date(content),
        amount_cents: find_total(content)
    }
  end

  # Only links on a KRA host count: the verify button opens this URL in the
  # browser, so a look-alike domain must not be treated as KRA's.
  defp kra_link(content) do
    with %URI{scheme: scheme, host: host} = uri when scheme in ["http", "https"] <-
           URI.parse(content),
         true <- is_binary(host) and kra_host?(String.downcase(host)) do
      {:ok, uri, URI.decode_query(uri.query || "")}
    else
      _ -> :error
    end
  end

  defp kra_host?(host), do: host == "kra.go.ke" or String.ends_with?(host, ".kra.go.ke")

  defp find_date(text) do
    cond do
      match = Regex.run(~r/\b(\d{4})-(\d{2})-(\d{2})\b/, text) ->
        [_, y, m, d] = match
        to_date(y, m, d)

      match = Regex.run(~r/\b(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})\b/, text) ->
        [_, d, m, y] = match
        to_date(y, m, d)

      true ->
        nil
    end
  end

  defp to_date(y, m, d) do
    case Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d)) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp find_total(text) do
    with [_, amount] <- Regex.run(~r/total[^0-9]{0,20}([\d,]+(?:\.\d{1,2})?)/i, text),
         {:ok, cents} <- RisitiApp.Transactions.parse_amount(amount) do
      cents
    else
      _ -> nil
    end
  end

  defp capture(regex, text) do
    case Regex.run(regex, text) do
      [_, value] -> value
      nil -> nil
    end
  end

  defp blank(source) do
    %{
      source: source,
      seller_pin: nil,
      branch_id: nil,
      invoice_number: nil,
      verify_url: nil,
      date: nil,
      amount_cents: nil,
      vendor: nil
    }
  end
end
