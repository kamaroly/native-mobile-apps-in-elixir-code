defmodule Risiti.Accounts.Fragments.Multitenancies do
  @moduledoc """
  What every resource kept in a team's own schema shares: the team is the
  tenant, and the actor's current team is used when no tenant is given.

      use Ash.Resource,
        ...,
        fragments: [Risiti.Accounts.Fragments.Multitenancies]
  """

  use Spark.Dsl.Fragment, of: Ash.Resource

  multitenancy do
    strategy :context
  end

  preparations do
    prepare Risiti.Preparations.SetTenant
  end

  changes do
    change Risiti.Changes.SetTenant
  end
end
