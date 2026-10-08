defmodule Risiti.Release do
  @moduledoc """
  Database tasks for the release, where there's no Mix. `bin/migrate` runs
  `migrate_all/0` on every deploy (`deploy/deploy.sh`).
  """
  @app :risiti

  @doc """
  Runs the `public` migrations, then the tenant migrations in every team's
  schema: what `mix ash.migrate` and `mix ash.migrate --tenants` do in
  development.
  """
  def migrate_all do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)

          tenant_migrations = Ecto.Migrator.migrations_path(repo, "tenant_migrations")

          for tenant <- repo.all_tenants() do
            Ecto.Migrator.run(repo, tenant_migrations, :up, all: true, prefix: tenant)
          end
        end)
    end
  end

  @doc "Rolls the `public` schema back to `version`."
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
