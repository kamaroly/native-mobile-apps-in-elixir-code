defmodule RisitiApp.PdfTest do
  use ExUnit.Case, async: true

  alias RisitiApp.Pdf

  doctest Pdf

  test "writes a PDF whose cross-reference table points at each object" do
    pdf =
      Pdf.render(
        [[{:text, 40, 800, 12, :bold, "Café (Nairobi) – 50\\50"}], [{:line, 0, 0, 10, 10, 0.5}]],
        "Test"
      )

    assert "%PDF-1.4" <> _ = pdf
    assert String.ends_with?(pdf, "%%EOF\n")
    # Latin-1 é, Windows-1252 en dash, escaped brackets and backslash.
    assert pdf =~ <<"(Caf", 0xE9, " \\(Nairobi\\) ", 0x96, " 50\\\\50)">>

    [_, xref_at] = Regex.run(~r/startxref\n(\d+)/, pdf)
    xref = binary_part(pdf, String.to_integer(xref_at), 4)
    assert xref == "xref"

    offsets = Regex.scan(~r/^(\d{10}) 00000 n $/m, pdf, capture: :all_but_first)

    for {[offset], n} <- Enum.with_index(offsets, 1) do
      assert binary_part(pdf, String.to_integer(offset), byte_size("#{n} 0 obj")) == "#{n} 0 obj"
    end
  end

  test "the title in the file's properties keeps characters like the en dash" do
    pdf = Pdf.render([[]], "Transactions – Last month")
    # "–" is U+2013: 2013 in UTF-16, after the FEFF byte-order mark.
    assert pdf =~ "/Title <FEFF005400720061006E00730061006300740069006F006E0073002020130020"
  end
end
