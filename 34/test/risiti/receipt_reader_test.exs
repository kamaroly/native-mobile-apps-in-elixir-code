defmodule Risiti.ReceiptReaderTest do
  use ExUnit.Case, async: true

  alias Risiti.Expenses.{OcrParser, ReceiptReader}

  # tesseract's TSV: level 5 rows are words, numbered block, paragraph, line.
  # Here "TOTAL" and its amount were read as two lines, side by side.
  @tsv """
  level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
  5\t1\t1\t1\t1\t1\t40\t10\t200\t20\t96\tNAIVAS
  5\t1\t1\t1\t1\t2\t250\t10\t200\t20\t96\tLIMITED
  5\t1\t2\t1\t1\t1\t40\t100\t90\t22\t95\tTOTAL
  5\t1\t3\t1\t1\t1\t400\t102\t120\t20\t94\t2,450.00
  5\t1\t4\t1\t1\t1\t40\t140\t90\t20\t95\tCASH
  5\t1\t5\t1\t1\t1\t400\t141\t120\t20\t94\t3,000.00
  """

  test "words become lines, and lines side by side become one row" do
    assert ReceiptReader.lines(@tsv) |> Enum.map(& &1.text) ==
             ["NAIVAS LIMITED", "TOTAL", "2,450.00", "CASH", "3,000.00"]

    assert @tsv |> ReceiptReader.lines() |> ReceiptReader.rows() ==
             "NAIVAS LIMITED\nTOTAL  2,450.00\nCASH  3,000.00"
  end

  test "so the phone's parser finds the total" do
    text = @tsv |> ReceiptReader.lines() |> ReceiptReader.rows()
    assert %{vendor: "Naivas Limited", amount_cents: 245_000} = OcrParser.parse(text)
  end

  @tag :pdftotext
  test "a PDF with text in it is read with pdftotext" do
    assert {:ok, %{text: text}} =
             ReceiptReader.read("test/fixtures/uploads/kamau_hardware.pdf", "application/pdf")

    assert %{vendor: "Kamau Hardware Limited", date: ~D[2026-10-06], amount_cents: 1_250_000} =
             OcrParser.parse(text, today: ~D[2026-10-07])
  end

  test "a type it can't read is an error" do
    assert {:error, {:unsupported, "text/plain"}} = ReceiptReader.read("mix.exs", "text/plain")
  end
end
