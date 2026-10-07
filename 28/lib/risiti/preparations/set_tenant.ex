defmodule Risiti.Preparations.SetTenant do
  @moduledoc "Reads: the actor's current team is the tenant, unless one was given."

  use Ash.Resource.Preparation

  @impl true
  def prepare(%{tenant: nil} = query, _opts, %{actor: %{current_team: team}})
      when is_binary(team),
      do: Ash.Query.set_tenant(query, team)

  def prepare(query, _opts, _context), do: query
end
