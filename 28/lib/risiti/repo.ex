defmodule Risiti.Repo do
  use AshPostgres.Repo,
    otp_app: :risiti

  @impl true
  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    ["ash-functions", "citext"]
  end

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  @impl true
  def prefer_transaction? do
    false
  end

  @impl true
  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end

  @doc "Every team's schema, for `mix ash.migrate --tenants` and releases."
  @impl true
  def all_tenants do
    for team <- Ash.read!(Risiti.Accounts.Team, authorize?: false), do: team.domain
  end
end
