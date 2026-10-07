defmodule RisitiApp.Transactions.Attachments do
  @moduledoc """
  Files attached to transactions, kept in `attachments/` in the app's
  private data folder (see `RisitiApp.DataDir`).

  A file is copied in as soon as it's added, so it stays readable after the
  camera or the file picker cleans up its temporary copy. If the
  transaction is never saved, the form deletes what it copied.
  """

  alias RisitiApp.DataDir
  alias RisitiApp.Transactions.Attachment

  @dir "attachments"

  # Enough for a phone photo or a scanned invoice of several pages.
  @max_size 10 * 1024 * 1024
  @max_count 5

  def max_count, do: @max_count

  @doc """
  Copies the file at `source` in and returns an unsaved attachment for it.
  `name` is what to show; `content_type` must be an image or a PDF.
  """
  def store(source, name, content_type) do
    with :ok <- check_type(content_type),
         {:ok, %File.Stat{size: size}} <- File.stat(source),
         :ok <- check_size(size) do
      file_name =
        "attachment-#{System.os_time(:millisecond)}-#{:rand.uniform(1_000_000)}" <>
          extension(name, content_type)

      with :ok <- File.cp(source, path(file_name)) do
        {:ok,
         %Attachment{file_name: file_name, name: name, content_type: content_type, size: size}}
      end
    end
  end

  @doc "Full path of a stored attachment."
  def path(file_name), do: Path.join(DataDir.path(@dir), Path.basename(file_name))

  @doc "Deletes stored attachment files. Missing files are fine."
  def delete(attachments) do
    Enum.each(attachments, &File.rm(path(&1.file_name)))
  end

  @doc """
  The type of a file nobody labelled, from its name.

      iex> RisitiApp.Transactions.Attachments.content_type("Invoice.PDF")
      "application/pdf"

      iex> RisitiApp.Transactions.Attachments.content_type("notes.txt")
      nil
  """
  def content_type(name) do
    case name |> Path.extname() |> String.downcase() do
      ext when ext in [".jpg", ".jpeg"] -> "image/jpeg"
      ".png" -> "image/png"
      ".webp" -> "image/webp"
      ".heic" -> "image/heic"
      ".pdf" -> "application/pdf"
      _ -> nil
    end
  end

  @doc """
  A file size for people.

      iex> RisitiApp.Transactions.Attachments.format_size(2_400_000)
      "2.3 MB"

      iex> RisitiApp.Transactions.Attachments.format_size(52_000)
      "50 KB"
  """
  def format_size(bytes) when bytes >= 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  def format_size(bytes), do: "#{max(div(bytes, 1024), 1)} KB"

  defp check_type("image/" <> _), do: :ok
  defp check_type("application/pdf"), do: :ok
  defp check_type(_type), do: {:error, :unsupported}

  defp check_size(size) when size > @max_size, do: {:error, :too_large}
  defp check_size(_size), do: :ok

  defp extension(name, content_type) do
    case Path.extname(name) do
      "" -> if content_type == "application/pdf", do: ".pdf", else: ".jpg"
      ext -> String.downcase(ext)
    end
  end
end
