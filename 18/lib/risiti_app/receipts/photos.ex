defmodule RisitiApp.Receipts.Photos do
  @moduledoc """
  Where receipt photos live: `receipt_photos/` in the app's private data
  directory, so they survive app updates and are removed with the app.

  The database stores only the file name; `path/1` turns it into a full path.
  The data directory is not the same on every install, so a stored absolute
  path could go stale.
  """

  @dir "receipt_photos"

  @doc "A fresh, unused path to save a new photo to."
  def new_path do
    name = "receipt-#{System.os_time(:millisecond)}-#{:rand.uniform(1_000_000)}.jpg"
    Path.join(dir(), name)
  end

  @doc "Copies the camera's temporary file in, and returns the name to store."
  def keep(tmp_path) do
    path = new_path()
    File.cp!(tmp_path, path)
    name(path)
  end

  @doc "Full path for a stored file name, or nil."
  def path(nil), do: nil
  def path(name), do: Path.join(dir(), Path.basename(name))

  @doc "The file name to store for a full path."
  def name(path), do: Path.basename(path)

  def exists?(nil), do: false
  def exists?(name), do: File.regular?(path(name))

  @doc "Deletes a stored photo. Missing files are fine."
  def delete(nil), do: :ok

  def delete(name) do
    _ = File.rm(path(name))
    :ok
  end

  def dir, do: RisitiApp.DataDir.path(@dir)
end
