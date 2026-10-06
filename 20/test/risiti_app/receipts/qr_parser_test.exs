defmodule RisitiApp.Receipts.QrParserTest do
  use ExUnit.Case, async: true

  alias RisitiApp.Receipts.QrParser

  test "splits an eTIMS link into seller PIN, branch and signature" do
    url =
      "https://etims.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=P051234567X00ABCDEF0123456789"

    assert %{
             source: "etims",
             seller_pin: "P051234567X",
             branch_id: "00",
             invoice_number: "ABCDEF0123456789",
             verify_url: ^url,
             vendor: nil,
             amount_cents: nil
           } = QrParser.parse(url)
  end

  test "accepts the eTIMS sandbox host" do
    url =
      "https://etims-sbx.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=P000000001G02JHEURBU6RQAMEF3Y"

    assert %{source: "etims", seller_pin: "P000000001G", branch_id: "02"} = QrParser.parse(url)
  end

  test "reads the invoice number from a TIMS invoice-checker link" do
    url =
      "https://itax.kra.go.ke/KRA-Portal/invoiceChk.htm?actionCode=loadPage&invoiceNo=0040799830000012345"

    assert %{source: "tims", invoice_number: "0040799830000012345", verify_url: ^url} =
             QrParser.parse(url)
  end

  test "a look-alike domain is not treated as KRA and gets no verify link" do
    url = "https://etims.kra.go.ke.evil.example/indexEtimsReceiptData?Data=P051234567X00ABC"

    assert %{source: "other", verify_url: nil} = QrParser.parse(url)
  end

  test "picks date, total and PIN out of a plain-text summary" do
    text = "SHOP STOP LTD\nPIN: P051234567X\nDate: 21/09/2026\nTOTAL KES 1,250.50"

    assert %{
             source: "other",
             seller_pin: "P051234567X",
             date: ~D[2026-09-21],
             amount_cents: 125_050
           } = QrParser.parse(text)
  end

  test "an unrelated QR code yields no receipt fields" do
    assert %{source: "other", date: nil, amount_cents: nil, seller_pin: nil} =
             QrParser.parse("WIFI:S:home;T:WPA;P:secret;;")
  end
end
