defmodule RisitiApp.DataDir do
  @moduledoc """
  The app's private data directory (next to the SQLite database), where
  receipt photos are kept. Files there survive app updates and are removed
  with the app.

  The directory isn't the same on every install, so the database stores
  file names only and resolves them here.
  """

  @doc "The subdirectory `name`, created if missing."
  def path(name) do
    path = Path.join(base(), name)
    File.mkdir_p!(path)
    path
  end

  defp base do
    case System.get_env("MOB_DATA_DIR") do
      nil -> RisitiApp.Repo.config() |> Keyword.fetch!(:database) |> Path.dirname()
      data_dir -> data_dir
    end
  end
end
