# The repo keeps its database in MOB_DATA_DIR (see RisitiApp.Repo.init/2).
# Point it at a throwaway folder so tests never touch a real database.
data_dir = Path.join(System.tmp_dir!(), "risiti_app_test")
File.rm_rf!(data_dir)
System.put_env("MOB_DATA_DIR", data_dir)

{:ok, _} = Application.ensure_all_started(:ecto_sqlite3)

# Migrate with an ordinary pool, then restart the repo on the test sandbox
# (config/config.exs sets `pool: Ecto.Adapters.SQL.Sandbox` for :test).
{:ok, repo} = RisitiApp.Repo.start_link(pool: DBConnection.ConnectionPool)
migrations = Path.expand("../priv/repo/migrations", __DIR__)
Ecto.Migrator.run(RisitiApp.Repo, migrations, :up, all: true, log: false)
Supervisor.stop(repo)

{:ok, _} = RisitiApp.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(RisitiApp.Repo, :manual)

RisitiApp.Components.register_all()

defmodule RisitiApp.ScreenHelpers do
  @moduledoc "Helpers shared by the screen tests."

  import Mob.ScreenCase, only: [tree: 1]

  @doc "Expands a screen's tree the way Mob does on the device."
  def rendered(view) do
    renderers = view.socket.__mob__[:list_renderers] || %{}

    view
    |> tree()
    |> Mob.Composite.expand(self())
    |> Mob.List.expand(renderers, self())
  end

  @doc "Use with `setup :checkout_repo`: each test runs in its own transaction."
  def checkout_repo(_context) do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RisitiApp.Repo)
  end

  @doc "Saves an expense, with defaults for anything not given."
  def insert_transaction(attrs \\ %{}) do
    defaults = %{
      date: RisitiApp.Transactions.today(),
      vendor: "Naivas Supermarket",
      amount_cents: 100_000,
      category: "Food & Groceries"
    }

    {:ok, transaction} =
      RisitiApp.Transactions.create_transaction(Map.merge(defaults, Map.new(attrs)))

    transaction
  end
end

ExUnit.start()
