defmodule RisitiApp.Pdf do
  @moduledoc """
  Just enough PDF to print a table: A4 pages of text in Helvetica (regular
  and bold), lines and shaded boxes. The phone has no PDF library, so this
  writes the file format directly.

  Coordinates are points (1/72 inch) from the bottom-left corner of the
  page. A page is a list of drawing operations:

    * `{:text, x, y, size, :regular | :bold, text}` — `text` is UTF-8; what
      the built-in fonts can't show (anything outside Windows-1252) prints
      as `?`;
    * `{:text, x, y, size, font, text, gray}` — the same in a gray from 0
      (black) to 1 (white);
    * `{:line, x1, y1, x2, y2, gray}`;
    * `{:box, x, y, width, height, gray}` — a filled rectangle.
  """

  @width 595
  @height 842

  # Helvetica's advance widths (per 1000 points of font size) for ASCII 32–126.
  @helvetica [278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278] ++
               [556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556] ++
               [1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778] ++
               [667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556] ++
               [333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556] ++
               [556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584]

  @widths @helvetica |> Enum.with_index(32) |> Map.new(fn {w, c} -> {c, w} end)

  # Characters Windows-1252 has outside Latin-1 that receipts and labels use.
  @cp1252 %{
    ?– => 0x96,
    ?— => 0x97,
    ?‘ => 0x91,
    ?’ => 0x92,
    ?“ => 0x93,
    ?” => 0x94,
    ?• => 0x95,
    ?… => 0x85,
    ?€ => 0x80
  }

  def page_size, do: {@width, @height}

  @doc """
  How wide `text` prints at `size` points. Bold is a little wider than
  regular; the estimate errs on the wide side.
  """
  def text_width(text, size, font \\ :regular) do
    units =
      text
      |> String.to_charlist()
      |> Enum.reduce(0, &(&2 + Map.get(@widths, &1, 556)))

    units * size / 1000 * if(font == :bold, do: 1.03, else: 1.0)
  end

  @doc """
  `text` cut to fit in `width` points, ending in "…" when it was cut.

      iex> RisitiApp.Pdf.fit("Naivas Supermarket Westlands", 60, 10)
      "Naivas Sup…"
  """
  def fit(text, width, size, font \\ :regular) do
    if text_width(text, size, font) <= width,
      do: text,
      else: cut(text, width, size, font)
  end

  defp cut(text, width, size, font) do
    text
    |> String.graphemes()
    |> Enum.reduce_while("", fn g, acc ->
      if text_width(acc <> g <> "…", size, font) <= width,
        do: {:cont, acc <> g},
        else: {:halt, acc}
    end)
    |> String.trim_trailing()
    |> Kernel.<>("…")
  end

  @doc "The PDF file for `pages`, with `title` in its properties."
  def render(pages, title) do
    page_count = length(pages)
    # Objects: 1 catalog, 2 page tree, 3 regular font, 4 bold font, 5 info,
    # then a page and its content stream for each page.
    page_ids = Enum.map(0..(page_count - 1)//1, &(6 + 2 * &1))

    fixed = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [#{Enum.map_join(page_ids, " ", &"#{&1} 0 R")}] /Count #{page_count} >>",
      font("Helvetica"),
      font("Helvetica-Bold"),
      "<< /Title #{text_string(title)} /Producer (Risiti) >>"
    ]

    page_objects =
      Enum.flat_map(Enum.zip(pages, page_ids), fn {ops, id} ->
        stream = content(ops)

        [
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{@width} #{@height}] " <>
            "/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents #{id + 1} 0 R >>",
          "<< /Length #{byte_size(stream)} >>\nstream\n" <> stream <> "\nendstream"
        ]
      end)

    objects = fixed ++ page_objects
    header = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n"

    {body, xref_at} =
      objects
      |> Enum.with_index(1)
      |> Enum.map_reduce(byte_size(header), fn {object, n}, offset ->
        chunk = "#{n} 0 obj\n#{object}\nendobj\n"
        {{chunk, offset}, offset + byte_size(chunk)}
      end)

    chunks = Enum.map(body, &elem(&1, 0))
    count = length(objects) + 1

    xref =
      [
        "xref\n0 #{count}\n0000000000 65535 f \n"
        | Enum.map(body, fn {_chunk, offset} ->
            String.pad_leading(Integer.to_string(offset), 10, "0") <> " 00000 n \n"
          end)
      ]

    trailer =
      "trailer\n<< /Size #{count} /Root 1 0 R /Info 5 0 R >>\nstartxref\n#{xref_at}\n%%EOF\n"

    IO.iodata_to_binary([header, chunks, xref, trailer])
  end

  defp font(name),
    do: "<< /Type /Font /Subtype /Type1 /BaseFont /#{name} /Encoding /WinAnsiEncoding >>"

  defp content(ops), do: ops |> Enum.map_join("\n", &op/1)

  defp op({:text, x, y, size, font, text}), do: op({:text, x, y, size, font, text, 0})

  defp op({:text, x, y, size, font, text, gray}) do
    f = if font == :bold, do: "F2", else: "F1"
    "#{num(gray)} g BT /#{f} #{num(size)} Tf #{num(x)} #{num(y)} Td #{string(text)} Tj ET"
  end

  defp op({:line, x1, y1, x2, y2, gray}),
    do: "#{num(gray)} G 0.5 w #{num(x1)} #{num(y1)} m #{num(x2)} #{num(y2)} l S"

  defp op({:box, x, y, w, h, gray}),
    do: "#{num(gray)} g #{num(x)} #{num(y)} #{num(w)} #{num(h)} re f"

  defp num(n) when is_integer(n), do: Integer.to_string(n)
  defp num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)

  # Text outside a page (the title in the file's properties) isn't in the
  # fonts' encoding: it's PDFDocEncoding, where Windows-1252's en dash is "Œ".
  # UTF-16 with a byte-order mark, written in hex, says any character.
  defp text_string(text) do
    utf16 = :unicode.characters_to_binary(text, :utf8, {:utf16, :big})
    "<FEFF" <> Base.encode16(utf16) <> ">"
  end

  # A PDF literal string in Windows-1252, with ( ) \ escaped.
  defp string(text) do
    bytes =
      text
      |> String.to_charlist()
      |> Enum.map(fn
        c when c in [?(, ?), ?\\] -> [?\\, c]
        c when c in 32..126 or c in 160..255 -> c
        c -> Map.get(@cp1252, c, ??)
      end)

    IO.iodata_to_binary(["(", bytes, ")"])
  end
end
