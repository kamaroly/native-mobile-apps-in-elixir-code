defmodule RisitiApp.Receipts.KraReceiptTest do
  use ExUnit.Case, async: true

  alias RisitiApp.Receipts.KraReceipt

  doctest KraReceipt

  # Saved copies of KRA's verification pages (buyer PIN replaced).
  defp fixture(name), do: File.read!(Path.join("test/fixtures/kra", name))

  test "reads an eTIMS receipt page" do
    assert {:ok, details} = KraReceipt.parse(fixture("etims_receipt.html"))

    assert details == %{
             vendor: "Stabex International Limited",
             date: ~D[2026-09-24],
             amount_cents: 199_845,
             description: "Unleaded",
             invoice_number: "KRACU0300010612/58385"
           }
  end

  test "reads an iTax (TIMS / ETR) invoice checker page" do
    assert {:ok, details} = KraReceipt.parse(fixture("tims_invoice.html"))

    assert details == %{
             vendor: "Quick Mart Limited",
             date: ~D[2026-09-24],
             amount_cents: 120_500,
             description: nil,
             invoice_number: "0040807890002542148"
           }
  end

  test "a page with no receipt on it is unrecognised" do
    assert KraReceipt.parse("<html><body>Invalid invoice</body></html>") ==
             {:error, :unrecognised}
  end
end
