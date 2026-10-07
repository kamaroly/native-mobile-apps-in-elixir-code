defmodule Risiti.Expenses.Storage do
  @moduledoc """
  Where receipt photos and attachments are kept: `<dir>/<team>/<file>`,
  with `<dir>` from `config :risiti, :expense_files_dir`. In production,
  point it at a folder that survives deploys; the release's own `priv/` is
  replaced every time.

  Only the file's name goes in the database.
  """

  @max_size 10 * 1024 * 1024

  @doc """
  Copies an upload in for `tenant`, and returns its stored name, type and
  size. Images and PDFs, up to 10 MB.
  """
  @spec store(String.t(), Plug.Upload.t()) ::
          {:ok, %{file: String.t(), content_type: String.t(), size: non_neg_integer()}}
          | {:error, :unsupported | :too_large | File.posix()}
  def store(tenant, %Plug.Upload{path: path, filename: name, content_type: type}) do
    with :ok <- check_type(type),
         {:ok, %File.Stat{size: size}} <- File.stat(path),
         :ok <- check_size(size) do
      file = "#{Ash.UUIDv7.generate()}#{extension(name, type)}"
      dir = dir(tenant)
      File.mkdir_p!(dir)

      with :ok <- File.cp(path, Path.join(dir, file)) do
        {:ok, %{file: file, content_type: type, size: size}}
      end
    end
  end

  @doc "The full path of a stored file, or nil if it's missing."
  @spec path(String.t(), String.t() | nil) :: String.t() | nil
  def path(_tenant, nil), do: nil

  def path(tenant, file) do
    full = Path.join(dir(tenant), Path.basename(file))
    if File.regular?(full), do: full
  end

  @doc "Removes stored files, skipping any already gone."
  @spec delete(String.t(), [String.t() | nil]) :: :ok
  def delete(tenant, files) do
    Enum.each(files, fn file ->
      if full = path(tenant, file), do: File.rm(full)
    end)
  end

  defp dir(tenant) do
    base =
      Application.get_env(:risiti, :expense_files_dir) ||
        Application.app_dir(:risiti, "priv/uploads")

    Path.join(base, Path.basename(tenant))
  end

  defp check_type("image/" <> _), do: :ok
  defp check_type("application/pdf"), do: :ok
  defp check_type(_type), do: {:error, :unsupported}

  defp check_size(size) when size > @max_size, do: {:error, :too_large}
  defp check_size(_size), do: :ok

  defp extension(name, type) do
    case Path.extname(name || "") do
      "" -> if type == "application/pdf", do: ".pdf", else: ".jpg"
      ext -> String.downcase(ext)
    end
  end
end
