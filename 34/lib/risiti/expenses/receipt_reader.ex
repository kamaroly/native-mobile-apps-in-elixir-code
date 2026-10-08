defmodule Risiti.Expenses.ReceiptReader do
  @moduledoc """
  Reads a receipt uploaded on the web the way the phone reads a photo:
  the text, one printed row per line, and the QR code if it has one.
  `Risiti.Expenses.OcrParser` and `Risiti.Expenses.QrParser` then pick the
  fields out, with the same rules as on the phone.

    * **Photos.** `tesseract` finds the lines of text, and they're rebuilt
      into rows the way the phone rebuilds ML Kit's: lines whose vertical
      centres are close are one row, read left to right, so "TOTAL" and
      "2,450.00" share a line even when they were read as two columns.
    * **PDFs.** A PDF with text in it (most eTIMS e-receipts) is read with
      `pdftotext -layout`, which keeps rows together already; a scanned
      PDF's first page is rendered with `pdftoppm` and read like a photo.
    * **QR codes** are read with `zbarimg`, from the photo or the PDF's
      first page.

  These come from the `tesseract-ocr`, `poppler-utils` and `zbar-tools`
  packages. A missing tool, or a read that fails, just leaves that part out.
  """

  require Logger

  @timeout :timer.seconds(45)

  # Fewer characters than this from pdftotext means a scan, not a text PDF.
  @min_pdf_text 20

  @type result :: %{text: String.t(), qr: String.t() | nil}

  @spec read(Path.t(), String.t()) :: {:ok, result()} | {:error, term()}
  def read(path, content_type) do
    task = Task.async(fn -> extract(path, content_type) end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, result}} ->
        {:ok, result}

      {:ok, {:error, reason}} ->
        Logger.info("Couldn't read receipt: #{inspect(reason)}")
        {:error, reason}

      nil ->
        {:error, :timeout}
    end
  end

  defp extract(path, "application/pdf") do
    with_page_image(path, fn image ->
      layout =
        case run("pdftotext", ["-layout", "-f", "1", "-l", "2", path, "-"]) do
          {:ok, text} -> if String.length(String.trim(text)) >= @min_pdf_text, do: {:ok, text}
          {:error, _reason} -> nil
        end

      found(layout || (image && ocr(image)) || {:error, :no_text}, image && qr(image))
    end)
  end

  defp extract(path, "image/" <> _), do: found(ocr(path), qr(path))
  defp extract(_path, type), do: {:error, {:unsupported, type}}

  defp found({:ok, text}, qr), do: {:ok, %{text: text, qr: qr}}
  defp found({:error, _reason}, qr) when is_binary(qr), do: {:ok, %{text: "", qr: qr}}
  defp found({:error, reason}, _qr), do: {:error, reason}

  # The PDF's first page as a PNG (nil if it can't be rendered), removed
  # once `fun` is done with it.
  defp with_page_image(pdf, fun) do
    prefix = Path.join(System.tmp_dir!(), "risiti-receipt-#{System.unique_integer([:positive])}")
    png = prefix <> ".png"

    try do
      args = ["-r", "300", "-f", "1", "-l", "1", "-singlefile", "-png", pdf, prefix]

      case run("pdftoppm", args) do
        {:ok, _} -> fun.(png)
        {:error, _reason} -> fun.(nil)
      end
    after
      File.rm(png)
    end
  end

  # ── Text ──────────────────────────────────────────────────────────────────

  defp ocr(image) do
    with {:ok, tsv} <- run("tesseract", [image, "stdout", "-l", "eng", "--psm", "3", "tsv"]) do
      case tsv |> lines() |> rows() do
        "" -> {:error, :no_text}
        text -> {:ok, text}
      end
    end
  end

  @doc """
  The lines in tesseract's TSV output. It has a row per word (level 5),
  numbered by block, paragraph and line; a line's box spans its words'.
  """
  @spec lines(String.t()) :: [
          %{text: String.t(), left: integer(), top: integer(), bottom: integer()}
        ]
  def lines(tsv) do
    tsv
    |> String.split(~r/\R/, trim: true)
    |> Enum.map(&String.split(&1, "\t"))
    |> Enum.flat_map(fn
      ["5", _page, block, par, line, _word, left, top, _width, height, _conf, word] ->
        case String.trim(word) do
          "" ->
            []

          word ->
            [
              %{
                line: {block, par, line},
                word: word,
                left: int(left),
                top: int(top),
                height: int(height)
              }
            ]
        end

      _other ->
        []
    end)
    |> Enum.chunk_by(& &1.line)
    |> Enum.map(fn words ->
      %{
        text: Enum.map_join(words, " ", & &1.word),
        left: words |> Enum.map(& &1.left) |> Enum.min(),
        top: words |> Enum.map(& &1.top) |> Enum.min(),
        bottom: words |> Enum.map(&(&1.top + &1.height)) |> Enum.max()
      }
    end)
  end

  @doc """
  The phone's row rebuilding (`rows` in `MobOcrBridge.kt`), step for step:
  lines sorted top to bottom, each joining the row above when its vertical
  centre is within half the smaller height of that row's average centre;
  each row read left to right, its pieces two spaces apart.
  """
  @spec rows([map()]) :: String.t()
  def rows(lines) do
    lines
    |> Enum.sort_by(&center/1)
    |> Enum.reduce([], fn
      line, [row | rest] = rows ->
        average = (row |> Enum.map(&center/1) |> Enum.sum()) / length(row)
        tallest = row |> Enum.map(&height/1) |> Enum.max()

        if abs(center(line) - average) < 0.5 * min(height(line), tallest),
          do: [[line | row] | rest],
          else: [[line] | rows]

      line, [] ->
        [[line]]
    end)
    |> Enum.reverse()
    |> Enum.map_join("\n", fn row ->
      row |> Enum.sort_by(& &1.left) |> Enum.map_join("  ", & &1.text)
    end)
  end

  defp center(%{top: top, bottom: bottom}), do: (top + bottom) / 2
  defp height(%{top: top, bottom: bottom}), do: bottom - top

  defp int(string) do
    case Integer.parse(string) do
      {n, _rest} -> n
      :error -> 0
    end
  end

  # ── QR code ───────────────────────────────────────────────────────────────

  # zbarimg exits with 4 when the image has no code.
  defp qr(image) do
    with {:ok, out} <-
           run("zbarimg", ["--quiet", "--nodbus", "--raw", "-Sdisable", "-Sqrcode.enable", image]),
         [qr | _] <- out |> String.split(~r/\R/, trim: true) |> Enum.map(&String.trim/1),
         true <- qr != "" do
      qr
    else
      _none -> nil
    end
  end

  defp run(command, args) do
    case System.find_executable(command) do
      nil ->
        {:error, {:missing, command}}

      exe ->
        case System.cmd(exe, args, stderr_to_stdout: false) do
          {out, 0} -> {:ok, out}
          {_out, status} -> {:error, {command, status}}
        end
    end
  end
end
